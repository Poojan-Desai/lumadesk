import CryptoKit
import Darwin
import Foundation
import LumaCore
import LumaServices

struct Options {
    var corpus: String?
    var output: String?
    var mode: RetrievalMode?
    var repetitions = 5
    var warmups = 1
    var disableSemantics = false
    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--disable-semantics" { disableSemantics = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw CorpusError.invalid("Missing value for \(flag).") }
            let value = arguments[index + 1]
            switch flag {
            case "--corpus": corpus = value
            case "--output": output = value
            case "--mode": guard let parsed = RetrievalMode(rawValue: value) else { throw CorpusError.invalid("Mode must be bm25, semantic or hybrid.") }; mode = parsed
            case "--repetitions": guard let number = Int(value), (1...100).contains(number) else { throw CorpusError.invalid("Use 1–100 repetitions.") }; repetitions = number
            case "--warmups": guard let number = Int(value), (0...10).contains(number) else { throw CorpusError.invalid("Use 0–10 warmups.") }; warmups = number
            default: throw CorpusError.invalid("Unknown option: \(flag).")
            }
            index += 2
        }
    }
}

struct QueryResult: Encodable {
    let id: String
    let status: String
    let effectiveMode: String
    let queryVectorAvailable: Bool
    let embeddedPassages: Int
    let eligiblePassages: Int
    let recallAt5: Double?
    let ndcgAt5: Double?
    let rankedDocumentIDs: [UUID]
    let milliseconds: [Double]
}
struct ModeResult: Encodable {
    let mode: RetrievalMode
    let status: String
    let modelInitializationMilliseconds: Double
    let indexMilliseconds: Double
    let coverage: IndexCoverage
    let evaluatedQueries: Int
    let queryCount: Int
    let semanticQueries: Int
    let fallbackQueries: Int
    let meanRecallAt5: Double?
    let meanNDCGAt5: Double?
    let queryMedianMilliseconds: Double?
    let queryP95Milliseconds: Double?
    let queries: [QueryResult]
}
struct Report: Encodable {
    let schema = "lumadesk-benchmark-report/v1"
    let generatedAt: String
    let corpusName: String
    let corpusSHA256: String
    let corpusProvenance: String
    let corpusLicense: String
    let documentCount: Int
    let queryCount: Int
    let operatingSystem: String
    let hardwareModel: String
    let cpuBrand: String
    let architecture: String
    let logicalProcessors: Int
    let physicalMemoryBytes: UInt64
    let peakProcessRSSBytes: Int64?
    let buildConfiguration: String
    let repetitions: Int
    let warmups: Int
    let semanticsDisabled: Bool
    let policy: String
    let modes: [ModeResult]
}
func milliseconds(since start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }
func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unavailable" }
    var value = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return "unavailable" }
    return String(cString: value)
}
func peakRSS() -> Int64? {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    return Int64(usage.ru_maxrss) // Darwin returns bytes, process lifetime high-water mark.
}
func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

func run() async throws {
    if Array(CommandLine.arguments.dropFirst()) == ["--help"] {
        print("""
        Usage: LumaBenchmark [--corpus path.json] [--output report.json]
                             [--mode bm25|semantic|hybrid] [--disable-semantics]
                             [--repetitions 1..100] [--warmups 0..10]
        Defaults: bundled synthetic fixture, all three modes, 5 repetitions, 1 warmup.
        Undefined quality metrics are omitted from JSON, never reported as zero.
        """)
        return
    }
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    let url: URL
    if let custom = options.corpus { url = URL(fileURLWithPath: custom) }
    else {
        guard let bundled = Bundle.module.url(forResource: "english-v1", withExtension: "json", subdirectory: "Fixtures") else { throw CorpusError.invalid("Bundled fixture is missing.") }
        url = bundled
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 5_000_000 else { throw CorpusError.invalid("Corpus JSON must be at most 5 MB.") }
    let bytes = try Data(contentsOf: url)
    let corpus = try JSONDecoder().decode(EvaluationCorpus.self, from: bytes)
    try corpus.validate()
    var results: [ModeResult] = []
    for mode in options.mode.map({ [$0] }) ?? RetrievalMode.allCases {
        let initializationStart = DispatchTime.now().uptimeNanoseconds
        let engine = RetrievalEngine(semanticEnabled: mode != .bm25 && !options.disableSemantics)
        let initializationMS = milliseconds(since: initializationStart)
        let indexStart = DispatchTime.now().uptimeNanoseconds
        _ = await engine.rebuild(corpus.libraryDocuments)
        let indexMS = milliseconds(since: indexStart)
        let coverage = await engine.coverage()
        var queries: [QueryResult] = []
        for query in corpus.queries {
            // Get every ranked passage before deduplicating; a long document must
            // not consume the complete top-five document candidate pool.
            let limit = coverage.passages
            for _ in 0..<options.warmups { _ = await engine.search(query.text, documentID: nil, mode: mode, limit: limit) }
            var timings: [Double] = []
            var response: RetrievalResponse?
            for _ in 0..<options.repetitions {
                let start = DispatchTime.now().uptimeNanoseconds
                response = await engine.search(query.text, documentID: nil, mode: mode, limit: limit)
                timings.append(milliseconds(since: start))
            }
            guard let response else { continue }
            let semanticReady = response.queryVectorAvailable && response.embeddedPassages > 0
            let unavailable = mode == .semantic && !semanticReady
            let metric = RetrievalEvaluation.score(rankedDocumentIDs: response.hits.map { $0.passage.documentID }, relevance: query.grades)
            let noRelevant = !query.grades.values.contains(where: { $0 > 0 })
            queries.append(QueryResult(id: query.id, status: unavailable ? "unavailable" : noRelevant ? "no-relevant-judgments" : "evaluated", effectiveMode: response.mode, queryVectorAvailable: response.queryVectorAvailable, embeddedPassages: response.embeddedPassages, eligiblePassages: response.eligiblePassages, recallAt5: unavailable ? nil : metric.recall, ndcgAt5: unavailable ? nil : metric.ndcg, rankedDocumentIDs: metric.rankedDocuments, milliseconds: timings))
        }
        let evaluated = queries.filter { $0.status == "evaluated" }
        let allTimings = queries.flatMap(\.milliseconds)
        results.append(ModeResult(mode: mode, status: mode == .semantic && queries.allSatisfy({ $0.status == "unavailable" }) ? "unavailable" : "completed", modelInitializationMilliseconds: initializationMS, indexMilliseconds: indexMS, coverage: coverage, evaluatedQueries: evaluated.count, queryCount: queries.count, semanticQueries: queries.filter { $0.queryVectorAvailable && $0.embeddedPassages > 0 }.count, fallbackQueries: mode == .hybrid ? queries.filter { !$0.queryVectorAvailable || $0.embeddedPassages == 0 }.count : 0, meanRecallAt5: mean(evaluated.compactMap(\.recallAt5)), meanNDCGAt5: mean(evaluated.compactMap(\.ndcgAt5)), queryMedianMilliseconds: RetrievalEvaluation.percentile(allTimings, quantile: 0.5), queryP95Milliseconds: RetrievalEvaluation.percentile(allTimings, quantile: 0.95), queries: queries))
    }
    #if DEBUG
    let configuration = "debug"
    #else
    let configuration = "release"
    #endif
    let report = Report(generatedAt: ISO8601DateFormatter().string(from: Date()), corpusName: corpus.name, corpusSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), corpusProvenance: corpus.provenance, corpusLicense: corpus.license, documentCount: corpus.documents.count, queryCount: corpus.queries.count, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, hardwareModel: sysctlString("hw.model"), cpuBrand: sysctlString("machdep.cpu.brand_string"), architecture: sysctlString("hw.machine"), logicalProcessors: ProcessInfo.processInfo.processorCount, physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory, peakProcessRSSBytes: peakRSS(), buildConfiguration: configuration, repetitions: options.repetitions, warmups: options.warmups, semanticsDisabled: options.disableSemantics, policy: "document-dedup-first-seen; k=5; recall=positive-doc-recall; DCG=(2^grade-1)/log2(rank+1); ideal=all-positive-judgments; undefined-quality-metrics=omitted; semantic=cosine-all-valid-vectors; hybrid=shipped-v1; raw-BM25(k1=1.2,b=0.75); query-timing=actor+query-embedding+rank; index-timing=segmentation+passage-embedding; peakRSS=whole-process-lifetime-bytes", modes: results)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    if let output = options.output { try data.write(to: URL(fileURLWithPath: output), options: .atomic) }
    else { print(String(decoding: data, as: UTF8.self)) }
}

do { try await run() }
catch { FileHandle.standardError.write(Data("Benchmark failed: \(error.localizedDescription)\n".utf8)); exit(1) }

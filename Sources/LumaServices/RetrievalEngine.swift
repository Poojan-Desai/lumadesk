import Foundation
import LumaCore
import NaturalLanguage

public struct RetrievalResponse: Sendable {
    public let hits: [SearchHit]
    public let mode: String
    public let queryVectorAvailable: Bool
    public let eligiblePassages: Int
    public let embeddedPassages: Int
}

public struct IndexCoverage: Codable, Sendable {
    public let passages: Int
    public let embeddedPassages: Int
    public let modelAvailable: Bool
    public let modelRevision: Int?
    public let vectorDimension: Int?
}

public actor RetrievalEngine {
    private var passages: [Passage] = []
    private var vectors: [String: [Double]] = [:]
    private let embedding: NLEmbedding?

    public init(semanticEnabled: Bool = true) {
        embedding = semanticEnabled ? NLEmbedding.sentenceEmbedding(for: .english) : nil
    }

    public func coverage() -> IndexCoverage {
        IndexCoverage(passages: passages.count, embeddedPassages: vectors.count, modelAvailable: embedding != nil, modelRevision: embedding?.revision, vectorDimension: embedding?.dimension)
    }

    public func rebuild(_ documents: [LibraryDocument]) -> Int {
        let next = TextSegmenter.passages(for: documents)
        // Passage IDs encode document/page/ordinal, so edited text can keep the
        // same ID. Reusing that vector would rank the replacement by old content.
        let previousText = Dictionary(passages.map { ($0.id, $0.text) }, uniquingKeysWith: { _, latest in latest })
        let unchangedIDs = Set(next.filter { previousText[$0.id] == $0.text }.map(\.id))
        vectors = vectors.filter { unchangedIDs.contains($0.key) }
        if let embedding {
            for passage in next where vectors[passage.id] == nil {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(passage.text)
                if recognizer.dominantLanguage == .english, let vector = embedding.vector(for: passage.text) {
                    vectors[passage.id] = vector
                }
            }
        }
        passages = next
        return vectors.count
    }

    public func search(_ query: String, documentID: UUID?, mode: RetrievalMode = .hybrid, limit: Int = 12) -> RetrievalResponse {
        let scoped = passages.filter { documentID == nil || $0.documentID == documentID }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(query)
        let language = recognizer.dominantLanguage
        let vector = mode != .bm25 && (language == .english || language == nil) ? embedding?.vector(for: query) : nil
        let hasSemantic = vector != nil && scoped.contains { vectors[$0.id] != nil }
        return RetrievalResponse(
            hits: SearchRanking.search(query: query, passages: scoped, queryVector: hasSemantic ? vector : nil, vectors: vectors, limit: limit, mode: mode),
            mode: mode == .bm25 ? "BM25 only" : mode == .semantic ? (hasSemantic ? "Semantic only" : "Semantic unavailable") : (hasSemantic ? "Semantic + keyword" : "Keyword search"),
            queryVectorAvailable: vector != nil,
            eligiblePassages: scoped.count,
            embeddedPassages: scoped.filter { vectors[$0.id] != nil }.count
        )
    }
}

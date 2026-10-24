import Foundation

public struct RetrievalMetrics: Codable, Sendable {
    public let recall: Double?
    public let ndcg: Double?
    public let retrievedRelevant: Int
    public let relevantDocuments: Int
    public let rankedDocuments: [UUID]
}

/// Document-level judgments. Repeated passages cannot occupy multiple ranks.
public enum RetrievalEvaluation {
    public static func score(rankedDocumentIDs: [UUID], relevance: [UUID: Int], cutoff: Int = 5) -> RetrievalMetrics {
        var seen: Set<UUID> = []
        let ranked = Array(rankedDocumentIDs.filter { seen.insert($0).inserted }.prefix(max(0, cutoff)))
        let positives = relevance.values.filter { $0 > 0 }
        let found = ranked.filter { relevance[$0, default: 0] > 0 }.count
        guard cutoff > 0, !positives.isEmpty else {
            return RetrievalMetrics(recall: nil, ndcg: nil, retrievedRelevant: found, relevantDocuments: positives.count, rankedDocuments: ranked)
        }
        func dcg(_ grades: [Int]) -> Double {
            grades.enumerated().reduce(0) { sum, item in
                sum + (pow(2, Double(item.element)) - 1) / log2(Double(item.offset + 2))
            }
        }
        let actual = dcg(ranked.map { max(0, relevance[$0, default: 0]) })
        let ideal = dcg(Array(positives.sorted(by: >).prefix(cutoff)))
        return RetrievalMetrics(recall: Double(found) / Double(positives.count), ndcg: ideal > 0 ? actual / ideal : nil, retrievedRelevant: found, relevantDocuments: positives.count, rankedDocuments: ranked)
    }

    /// Nearest-rank percentile; one observed value remains that value.
    public static func percentile(_ values: [Double], quantile: Double) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite && $0 >= 0 }), quantile.isFinite, quantile >= 0, quantile <= 1 else { return nil }
        let sorted = values.sorted()
        return sorted[max(0, Int(ceil(quantile * Double(sorted.count))) - 1)]
    }
}

public struct EvaluationCorpus: Decodable, Sendable {
    public let schema: String
    public let name: String
    public let provenance: String
    public let license: String
    public let documents: [Document]
    public let queries: [Query]
    public struct Document: Decodable, Sendable {
        public let id: UUID
        public let title: String
        public let pages: [Page]
    }
    public struct Page: Decodable, Sendable {
        public let number: Int
        public let text: String
    }
    public struct Query: Decodable, Sendable {
        public let id: String
        public let text: String
        public let relevance: [String: Int]
        public var grades: [UUID: Int] {
            Dictionary(uniqueKeysWithValues: relevance.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
        }
    }
    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw CorpusError.invalid(message) }
        }
        try require(schema == "lumadesk-evaluation/v1", "Unsupported corpus schema.")
        try require([name, provenance, license].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "Describe corpus provenance and license.")
        try require(!documents.isEmpty && documents.count <= 500 && !queries.isEmpty && queries.count <= 200, "Use 1–500 documents and 1–200 queries.")
        let ids = Set(documents.map(\.id))
        try require(ids.count == documents.count, "Document IDs must be unique.")
        try require(Set(queries.map(\.id)).count == queries.count, "Query IDs must be unique.")
        try require(documents.reduce(0, { $0 + $1.pages.reduce(0) { $0 + $1.text.count } }) <= 2_000_000, "Corpus exceeds two million characters.")
        for document in documents {
            try require(!document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !document.pages.isEmpty, "Each document needs a title and pages.")
            try require(Set(document.pages.map(\.number)).count == document.pages.count, "Page numbers must be unique per document.")
            for page in document.pages { try require(page.number > 0 && !page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Pages need positive numbers and nonempty text.") }
        }
        for query in queries {
            try require(!query.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && query.text.count <= 500, "Query ID is required; text is limited to 500 characters.")
            var canonicalIDs: Set<UUID> = []
            for (id, grade) in query.relevance {
                guard let uuid = UUID(uuidString: id), ids.contains(uuid), canonicalIDs.insert(uuid).inserted, (0...3).contains(grade) else { throw CorpusError.invalid("Judgments require unique corpus document IDs and grades 0–3.") }
            }
        }
    }
    public var libraryDocuments: [LibraryDocument] {
        documents.map { doc in
            LibraryDocument(id: doc.id, title: doc.title, kind: "Synthetic evaluation", importedAt: Date(timeIntervalSince1970: 0), pages: doc.pages.map { SourcePage(number: $0.number, text: $0.text, extraction: "Original synthetic benchmark text") }, isSample: true)
        }
    }
}

public enum CorpusError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

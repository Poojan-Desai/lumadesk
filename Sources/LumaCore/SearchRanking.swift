import Foundation

/// Default hybrid preserves the app's shipped weighting and admission rules.
/// Evaluation baselines expose raw BM25 or cosine without the other signal.
public enum RetrievalMode: String, CaseIterable, Codable, Sendable {
    case bm25, semantic, hybrid
}

public enum SearchRanking {
    private static let stopWords: Set<String> = ["a", "an", "and", "are", "as", "at", "be", "by", "do", "does", "for", "from", "how", "i", "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "was", "what", "when", "where", "which", "who", "why", "with"]

    public static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    public static func cosine(_ left: [Double], _ right: [Double]) -> Double? {
        guard !left.isEmpty, left.count == right.count, left.allSatisfy(\.isFinite), right.allSatisfy(\.isFinite) else { return nil }
        let dot = zip(left, right).reduce(0.0) { $0 + $1.0 * $1.1 }
        let leftNorm = sqrt(left.reduce(0) { $0 + $1 * $1 })
        let rightNorm = sqrt(right.reduce(0) { $0 + $1 * $1 })
        guard leftNorm > 0, rightNorm > 0 else { return nil }
        let similarity = dot / (leftNorm * rightNorm)
        guard similarity.isFinite else { return nil }
        return max(-1, min(1, similarity))
    }

    /// Convenience for one-off ranking. Repeated searches should reuse an
    /// immutable LexicalSearchIndex rather than tokenize the library each time.
    public static func search(query: String, passages: [Passage], queryVector: [Double]? = nil, vectors: [String: [Double]] = [:], limit: Int = 12, mode: RetrievalMode = .hybrid) -> [SearchHit] {
        LexicalSearchIndex(passages: passages).search(query: query, queryVector: queryVector, vectors: vectors, limit: limit, mode: mode)
    }
}

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

    /// Hybrid BM25 and cosine ranking. Semantic-only matches use a conservative
    /// similarity floor; results are evidence to inspect, never generated answers.
    public static func search(query: String, passages: [Passage], queryVector: [Double]? = nil, vectors: [String: [Double]] = [:], limit: Int = 12, mode: RetrievalMode = .hybrid) -> [SearchHit] {
        let terms = Set(tokens(query))
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !passages.isEmpty, limit > 0 else { return [] }
        if mode != .semantic && terms.isEmpty { return [] }
        let tokenLists = passages.map { tokens($0.text) }
        let averageLength = max(1, Double(tokenLists.reduce(0) { $0 + $1.count }) / Double(passages.count))
        var documentFrequency: [String: Int] = [:]
        for list in tokenLists {
            for token in Set(list) where terms.contains(token) { documentFrequency[token, default: 0] += 1 }
        }
        var hits: [SearchHit] = []
        for (index, passage) in passages.enumerated() {
            let frequency = Dictionary(tokenLists[index].map { ($0, 1) }, uniquingKeysWith: +)
            let matchedTerms = terms.filter { frequency[$0] != nil }.sorted()
            var bm25 = 0.0
            for term in matchedTerms {
                let df = Double(documentFrequency[term, default: 0])
                let idf = log(1 + (Double(passages.count) - df + 0.5) / (df + 0.5))
                let tf = Double(frequency[term, default: 0])
                bm25 += idf * (tf * 2.2) / (tf + 1.2 * (0.25 + 0.75 * Double(tokenLists[index].count) / averageLength))
            }
            let similarity: Double?
            if let queryVector, let vector = vectors[passage.id] { similarity = cosine(queryVector, vector) } else { similarity = nil }
            let score: Double
            switch mode {
            case .bm25:
                guard bm25 > 0 else { continue }
                score = bm25
            case .semantic:
                guard let similarity else { continue }
                score = similarity // Rank all valid vectors; no lexical gate or product floor.
            case .hybrid:
                guard !matchedTerms.isEmpty || (similarity ?? -1) >= 0.55 else { continue }
                let coverage = Double(matchedTerms.count) / Double(terms.count)
                let lexicalScore = bm25 / (bm25 + 1) * 0.75 + coverage * 0.25
                score = similarity.map { 0.60 * lexicalScore + 0.40 * max(0, $0) } ?? lexicalScore
            }
            hits.append(SearchHit(passage: passage, relevance: score, matchedTerms: matchedTerms, semanticSimilarity: mode == .bm25 ? nil : similarity))
        }
        return Array(hits.sorted {
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            if $0.passage.documentTitle != $1.passage.documentTitle { return $0.passage.documentTitle < $1.passage.documentTitle }
            if $0.passage.page != $1.passage.page { return $0.passage.page < $1.passage.page }
            return $0.id < $1.id
        }.prefix(limit))
    }
}

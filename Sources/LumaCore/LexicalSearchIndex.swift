import Foundation

/// Immutable passage statistics built once per library rebuild. Source filtering
/// still computes BM25 corpus statistics within the selected document scope.
/// A new index must be created after text, metadata, or source membership changes.
public struct LexicalSearchIndex: Sendable {
    private struct Entry: Sendable {
        let passage: Passage
        let frequencies: [String: Int]
        let length: Int
    }
    private let entries: [Entry]

    public init(passages: [Passage]) {
        entries = passages.map { passage in
            let tokens = SearchRanking.tokens(passage.text)
            return Entry(passage: passage, frequencies: Dictionary(tokens.map { ($0, 1) }, uniquingKeysWith: +), length: tokens.count)
        }
    }

    /// Hybrid BM25 and cosine ranking. Semantic-only matches use a conservative
    /// similarity floor; results are evidence to inspect, never generated answers.
    public func search(query: String, documentID: UUID? = nil, queryVector: [Double]? = nil, vectors: [String: [Double]] = [:], limit: Int = 12, mode: RetrievalMode = .hybrid) -> [SearchHit] {
        let scoped = entries.filter { documentID == nil || $0.passage.documentID == documentID }
        let passages = scoped.map(\.passage)
        let terms = Set(SearchRanking.tokens(query))
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !passages.isEmpty, limit > 0 else { return [] }
        if mode != .semantic && terms.isEmpty { return [] }
        let averageLength = max(1, Double(scoped.reduce(0) { $0 + $1.length }) / Double(passages.count))
        var documentFrequency: [String: Int] = [:]
        for entry in scoped {
            for term in terms where entry.frequencies[term] != nil { documentFrequency[term, default: 0] += 1 }
        }
        var hits: [SearchHit] = []
        for (index, passage) in passages.enumerated() {
            let frequency = scoped[index].frequencies
            let matchedTerms = terms.filter { frequency[$0] != nil }.sorted()
            var bm25 = 0.0
            for term in matchedTerms {
                let df = Double(documentFrequency[term, default: 0])
                let idf = log(1 + (Double(passages.count) - df + 0.5) / (df + 0.5))
                let tf = Double(frequency[term, default: 0])
                bm25 += idf * (tf * 2.2) / (tf + 1.2 * (0.25 + 0.75 * Double(scoped[index].length) / averageLength))
            }
            let similarity: Double?
            if let queryVector, let vector = vectors[passage.id] { similarity = SearchRanking.cosine(queryVector, vector) } else { similarity = nil }
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

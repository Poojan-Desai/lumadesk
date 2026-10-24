import Foundation
import LumaCore

extension ValidationSuite {
    /// Golden metric cases and adversarial fixtures are independent of an Apple
    /// embedding model, so scoring and baseline regressions remain reproducible.
    public static func runEvaluation() -> [ValidationResult] {
        var results: [ValidationResult] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            results.append(ValidationResult(name: name, passed: condition(), detail: ""))
        }
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let c = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let grades = [a: 3, b: 2, c: 1]
        let deduplicated = RetrievalEvaluation.score(rankedDocumentIDs: [c, c, a, b], relevance: grades, cutoff: 2)
        check("Evaluation deduplicates documents before applying cutoff", deduplicated.rankedDocuments == [c, a] && deduplicated.retrievedRelevant == 2 && abs((deduplicated.recall ?? 0) - 2.0 / 3.0) < 1e-12)
        // DCG([1,3]) / IDCG([3,2]) with exponential gains, rank two discount log2(3).
        let expectedNDCG = (1 + 7 / log2(3.0)) / (7 + 3 / log2(3.0))
        check("Graded NDCG matches a hand-calculated golden case", abs((deduplicated.ndcg ?? 0) - expectedNDCG) < 1e-12)
        let perfect = RetrievalEvaluation.score(rankedDocumentIDs: [a, b, c], relevance: grades)
        check("Perfect retrieval scores unit recall and NDCG", perfect.recall == 1 && perfect.ndcg == 1)
        let missed = RetrievalEvaluation.score(rankedDocumentIDs: [], relevance: grades)
        check("Missing ranked results score zero for judged queries", missed.recall == 0 && missed.ndcg == 0)
        let unjudged = RetrievalEvaluation.score(rankedDocumentIDs: [a], relevance: [a: 0])
        check("No positive judgments yield null metrics rather than success", unjudged.recall == nil && unjudged.ndcg == nil && unjudged.relevantDocuments == 0)
        let zeroCutoff = RetrievalEvaluation.score(rankedDocumentIDs: [a], relevance: grades, cutoff: 0)
        check("Nonpositive evaluation cutoffs return no ranks or metrics", zeroCutoff.rankedDocuments.isEmpty && zeroCutoff.recall == nil && zeroCutoff.ndcg == nil && RetrievalEvaluation.score(rankedDocumentIDs: [a], relevance: grades, cutoff: -1).rankedDocuments.isEmpty)
        check("Nearest-rank percentiles handle unsorted and single samples", RetrievalEvaluation.percentile([4, 1, 3, 2], quantile: 0.5) == 2 && RetrievalEvaluation.percentile([4, 1, 3, 2], quantile: 0.95) == 4 && RetrievalEvaluation.percentile([7], quantile: 0.95) == 7)
        check("Percentiles reject invalid timings and quantiles", RetrievalEvaluation.percentile([], quantile: 0.5) == nil && RetrievalEvaluation.percentile([.nan], quantile: 0.5) == nil && RetrievalEvaluation.percentile([-1], quantile: 0.5) == nil && RetrievalEvaluation.percentile([1], quantile: 1.1) == nil)

        let documents = [
            LibraryDocument(id: a, title: "Lexical match", kind: "TXT", pages: [SourcePage(number: 1, text: "Privacy privacy documents", extraction: "Original text")]),
            LibraryDocument(id: b, title: "Semantic match", kind: "TXT", pages: [SourcePage(number: 1, text: "Confidential notes", extraction: "Original text")])
        ]
        let passages = TextSegmenter.passages(for: documents)
        let vectors = [passages[0].id: [-1.0, 0], passages[1].id: [1.0, 0]]
        let baseline = SearchRanking.search(query: "privacy", passages: passages, queryVector: [1, 0], vectors: vectors, mode: .bm25)
        check("Pure BM25 ignores semantic vectors and nonlexical documents", baseline.count == 1 && baseline.first?.passage.documentID == a && baseline.first?.semanticSimilarity == nil)
        let semantic = SearchRanking.search(query: "privacy", passages: passages, queryVector: [1, 0], vectors: vectors, mode: .semantic)
        check("Pure cosine ranks weak and negative similarities without hybrid gates", semantic.map { $0.passage.documentID } == [b, a] && semantic.last?.relevance == -1)
        check("Semantic baseline does not fall back to lexical matches", SearchRanking.search(query: "privacy", passages: passages, mode: .semantic).isEmpty)
        check("Semantic baseline can evaluate all-stopword nonempty queries", SearchRanking.search(query: "what is it", passages: passages, queryVector: [1, 0], vectors: vectors, mode: .semantic).count == 2)
        check("Empty semantic queries never fabricate results", SearchRanking.search(query: "  ", passages: passages, queryVector: [1, 0], vectors: vectors, mode: .semantic).isEmpty)
        check("Default app ranking remains explicit hybrid ranking", SearchRanking.search(query: "privacy", passages: passages, queryVector: [1, 0], vectors: vectors).map(\.id) == SearchRanking.search(query: "privacy", passages: passages, queryVector: [1, 0], vectors: vectors, mode: .hybrid).map(\.id))

        let idText = a.uuidString
        let valid: [String: Any] = ["schema": "lumadesk-evaluation/v1", "name": "Synthetic", "provenance": "Original test fixture", "license": "CC0-1.0", "documents": [["id": idText, "title": "Source", "pages": [["number": 1, "text": "A source passage"]]]], "queries": [["id": "q1", "text": "source", "relevance": [idText: 3]]]]
        func accepts(_ object: [String: Any]) -> Bool {
            do {
                let corpus = try JSONDecoder().decode(EvaluationCorpus.self, from: JSONSerialization.data(withJSONObject: object))
                try corpus.validate()
                return true
            } catch { return false }
        }
        check("Valid synthetic evaluation corpus is accepted", accepts(valid))
        var changed = valid; changed["schema"] = "unknown/v2"
        check("Unsupported evaluation schemas are rejected", !accepts(changed))
        changed = valid; changed["queries"] = []
        check("Empty evaluation query sets are rejected", !accepts(changed))
        changed = valid; changed["queries"] = [["id": "q1", "text": "source", "relevance": [b.uuidString: 3]]]
        check("Judgments for absent corpus documents are rejected", !accepts(changed))
        changed = valid; changed["queries"] = [["id": "q1", "text": "source", "relevance": [idText: 4]]]
        check("Out-of-range relevance grades are rejected", !accepts(changed))
        changed = valid; changed["queries"] = [["id": "q1", "text": "source", "relevance": [idText: 3]], ["id": "q1", "text": "another", "relevance": [:]]]
        check("Duplicate evaluation query IDs are rejected", !accepts(changed))
        changed = valid; changed["name"] = "  \n"
        check("Whitespace-only evaluation metadata is rejected", !accepts(changed))
        changed = valid; changed["documents"] = [["id": idText, "title": "Source", "pages": [["number": 1, "text": "first"], ["number": 1, "text": "second"]]]]
        check("Ambiguous duplicate source page numbers are rejected", !accepts(changed))
        return results
    }
}

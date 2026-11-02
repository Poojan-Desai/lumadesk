import Foundation
import LumaCore

extension ValidationSuite {
    static func runSearchPresentation() -> [ValidationResult] {
        var results: [ValidationResult] = []
        func check(_ name: String, _ condition: Bool) {
            results.append(ValidationResult(name: name, passed: condition, detail: ""))
        }
        let source = UUID()
        let passage = Passage(id: "sample:1:0", documentID: source, documentTitle: "Private source", page: 1,
                              text: "Documents remain private.", extraction: "Original text")
        let hit = SearchHit(passage: passage, relevance: 1, matchedTerms: ["private"], semanticSimilarity: nil)
        var state = SearchPresentation()
        let first = state.begin(query: " private ", documentID: nil)!
        check("Pending search cannot export earlier evidence", state.isSearching && state.hits.isEmpty && state.exportRequest(query: "private", documentID: nil) == nil)
        check("Completed search retains its exact query context", state.finish(first, hits: [hit], mode: "Keyword search") && state.exportRequest(query: "private", documentID: nil)?.query == "private")
        check("Changed input cannot export before a new search is queued", state.exportRequest(query: "forest", documentID: nil) == nil)
        check("Changed source scope cannot export old citations", state.exportRequest(query: "private", documentID: source) == nil)
        let next = state.begin(query: "forest", documentID: source)!
        check("New query clears prior hits before retrieval", state.hits.isEmpty && state.isSearching)
        check("Superseded response cannot restore old query hits", !state.finish(first, hits: [hit], mode: "Old mode") && state.hits.isEmpty && state.isSearching)
        _ = state.finish(next, hits: [hit], mode: "Keyword search")
        check("Only the completed query and scope can export", state.exportRequest(query: "forest", documentID: source) == next && state.exportRequest(query: "private", documentID: source) == nil)
        let repeated = state.begin(query: "forest", documentID: source)!
        check("Repeated query still rejects a previous response", !state.finish(next, hits: [hit], mode: "Old mode") && state.isSearching)
        state.invalidate()
        check("Library mutation clears presentation and rejects in-flight responses", state.hits.isEmpty && !state.isSearching && !state.finish(repeated, hits: [hit], mode: "Old mode") && state.exportRequest(query: "forest", documentID: source) == nil)
        check("Empty query leaves no pending result context", state.begin(query: " \n ", documentID: nil) == nil && state.hits.isEmpty && !state.isSearching)
        return results
    }
}

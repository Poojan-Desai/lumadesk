import Foundation
import LumaCore

extension ValidationSuite {
    public static func runLexicalIndex() -> [ValidationResult] {
        var results: [ValidationResult] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            results.append(ValidationResult(name: name, passed: condition(), detail: ""))
        }
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let passages = [
            Passage(id: "first", documentID: firstID, documentTitle: "Private notes", page: 1, text: "privacy privacy local", extraction: "Original text"),
            Passage(id: "second", documentID: firstID, documentTitle: "Private notes", page: 2, text: "local storage", extraction: "Original text"),
            Passage(id: "third", documentID: secondID, documentTitle: "Astronomy", page: 1, text: "privacy astronomy astronomy astronomy", extraction: "Vision OCR")
        ]
        let index = LexicalSearchIndex(passages: passages)
        let scoped = index.search(query: "privacy", documentID: firstID, mode: .bm25)
        // Scoped N=2, df=1, tf=2, length=3, average length=2.5.
        let expected = log(2.0) * 4.4 / (2.0 + 1.2 * (0.25 + 0.75 * 3.0 / 2.5))
        check("Cached BM25 retains the hand-calculated scoped score", scoped.count == 1 && abs((scoped.first?.relevance ?? 0) - expected) < 0.000000001)
        let global = index.search(query: "privacy", mode: .bm25)
        check("Cached scope excludes other sources and recomputes corpus statistics", global.count == 2 && global.first?.relevance != scoped.first?.relevance && scoped.allSatisfy { $0.passage.documentID == firstID })
        let repeated = index.search(query: "privacy", documentID: firstID, mode: .bm25)
        check("Repeated cached queries retain deterministic scores and citations", repeated.map(\.id) == scoped.map(\.id) && repeated.map(\.relevance) == scoped.map(\.relevance) && repeated.first?.passage.page == 1)
        check("Unknown cached source scope returns no matches", index.search(query: "privacy", documentID: UUID(), mode: .bm25).isEmpty)
        let revised = Passage(id: "first", documentID: firstID, documentTitle: "Renamed notes", page: 7, text: "waterfall mountain", extraction: "Revised OCR")
        let rebuilt = LexicalSearchIndex(passages: [revised])
        let revisedHits = rebuilt.search(query: "waterfall", mode: .bm25)
        check("Rebuilt lexical index drops obsolete terms under stable passage IDs", rebuilt.search(query: "privacy", mode: .bm25).isEmpty && revisedHits.count == 1)
        check("Rebuilt lexical index refreshes source citation metadata", revisedHits.first?.passage.documentTitle == "Renamed notes" && revisedHits.first?.passage.page == 7 && revisedHits.first?.passage.extraction == "Revised OCR")
        let semantic = index.search(query: "confidential", queryVector: [1, 0], vectors: ["first": [1, 0]], mode: .hybrid)
        check("Cached hybrid admits strong semantic matches without keywords", semantic.count == 1 && semantic.first?.id == "first" && semantic.first?.matchedTerms.isEmpty == true)
        check("Empty cached libraries and nonpositive limits remain safe", LexicalSearchIndex(passages: []).search(query: "privacy").isEmpty && index.search(query: "privacy", limit: 0).isEmpty)
        return results
    }
}

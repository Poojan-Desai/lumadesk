import Foundation

public struct SourcePage: Codable, Hashable, Sendable {
    public let number: Int
    public let text: String
    public let extraction: String
    public init(number: Int, text: String, extraction: String) {
        self.number = number; self.text = text; self.extraction = extraction
    }
}

public struct LibraryDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let kind: String
    public let importedAt: Date
    public let pages: [SourcePage]
    public let isSample: Bool
    public init(id: UUID = UUID(), title: String, kind: String, importedAt: Date = Date(), pages: [SourcePage], isSample: Bool = false) {
        self.id = id; self.title = title; self.kind = kind; self.importedAt = importedAt; self.pages = pages; self.isSample = isSample
    }
    public var wordCount: Int { pages.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }
}

public struct Passage: Identifiable, Hashable, Sendable {
    public let id: String
    public let documentID: UUID
    public let documentTitle: String
    public let page: Int
    public let text: String
    public let extraction: String
    public init(id: String, documentID: UUID, documentTitle: String, page: Int, text: String, extraction: String) {
        self.id = id; self.documentID = documentID; self.documentTitle = documentTitle; self.page = page; self.text = text; self.extraction = extraction
    }
}

public struct SearchHit: Identifiable, Sendable {
    public var id: String { passage.id }
    public let passage: Passage
    /// A retrieval ranking score. This is not an answer correctness probability.
    public let relevance: Double
    public let matchedTerms: [String]
    public let semanticSimilarity: Double?
    public init(passage: Passage, relevance: Double, matchedTerms: [String], semanticSimilarity: Double?) {
        self.passage = passage; self.relevance = relevance; self.matchedTerms = matchedTerms; self.semanticSimilarity = semanticSimilarity
    }
}

public enum TextSegmenter {
    public static func chunks(_ text: String, maxWords: Int = 120, overlapWords: Int = 20) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        let size = max(1, maxWords)
        let overlap = max(0, min(overlapWords, size - 1))
        var result: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + size, words.count)
            result.append(words[start..<end].joined(separator: " "))
            guard end < words.count else { break }
            start = end - overlap
        }
        return result
    }
    public static func passages(for documents: [LibraryDocument]) -> [Passage] {
        documents.flatMap { document in
            document.pages.flatMap { page in
                chunks(page.text).enumerated().map { index, text in
                    Passage(id: "\(document.id.uuidString):\(page.number):\(index)", documentID: document.id, documentTitle: document.title, page: page.number, text: text, extraction: page.extraction)
                }
            }
        }
    }
}

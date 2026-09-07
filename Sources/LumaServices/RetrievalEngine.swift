import Foundation
import LumaCore
import NaturalLanguage

public struct RetrievalResponse: Sendable {
    public let hits: [SearchHit]
    public let mode: String
}

public actor RetrievalEngine {
    private var passages: [Passage] = []
    private var vectors: [String: [Double]] = [:]
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    public init() {}

    public func rebuild(_ documents: [LibraryDocument]) -> Int {
        let next = TextSegmenter.passages(for: documents)
        let validIDs = Set(next.map(\.id))
        vectors = vectors.filter { validIDs.contains($0.key) }
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

    public func search(_ query: String, documentID: UUID?) -> RetrievalResponse {
        let scoped = passages.filter { documentID == nil || $0.documentID == documentID }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(query)
        let language = recognizer.dominantLanguage
        let vector = (language == .english || language == nil) ? embedding?.vector(for: query) : nil
        let hasSemantic = vector != nil && scoped.contains { vectors[$0.id] != nil }
        return RetrievalResponse(
            hits: SearchRanking.search(query: query, passages: scoped, queryVector: hasSemantic ? vector : nil, vectors: vectors),
            mode: hasSemantic ? "Semantic + keyword" : "Keyword search"
        )
    }
}

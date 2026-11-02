import Foundation

/// A response belongs to one exact request, even when its query text repeats.
public struct SearchRequest: Equatable, Sendable {
    fileprivate let identity: UUID
    public let query: String
    public let documentID: UUID?
}

/// Shared presentation state used by the app and the standalone validation suite.
/// Beginning a request removes earlier evidence before debounce or retrieval.
public struct SearchPresentation: Sendable {
    public private(set) var hits: [SearchHit] = []
    public private(set) var mode = "Keyword search"
    public private(set) var isSearching = false
    private var pending: SearchRequest?
    private var completed: SearchRequest?

    public init() {}

    public mutating func begin(query: String, documentID: UUID?) -> SearchRequest? {
        invalidate()
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let request = SearchRequest(identity: UUID(), query: input, documentID: documentID)
        pending = request
        isSearching = true
        return request
    }

    @discardableResult
    public mutating func finish(_ request: SearchRequest, hits: [SearchHit], mode: String) -> Bool {
        guard pending == request else { return false }
        self.hits = hits
        self.mode = mode
        pending = nil
        completed = request
        isSearching = false
        return true
    }

    public mutating func invalidate() {
        pending = nil
        completed = nil
        hits = []
        isSearching = false
    }

    /// Recheck input/scope too, including the interval before SwiftUI onChange.
    public func exportRequest(query: String, documentID: UUID?) -> SearchRequest? {
        guard !isSearching, !hits.isEmpty, let completed,
              completed.query == query.trimmingCharacters(in: .whitespacesAndNewlines),
              completed.documentID == documentID else { return nil }
        return completed
    }
}

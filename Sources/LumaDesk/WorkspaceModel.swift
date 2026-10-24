import AppKit
import Foundation
import LumaCore
import LumaServices
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var documents: [LibraryDocument] = []
    @Published var query = ""
    @Published var selectedDocumentID: UUID?
    @Published var selectedHitID: String?
    @Published private(set) var hits: [SearchHit] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isSearching = false
    @Published private(set) var status = "Ready when you are"
    @Published private(set) var searchMode = "Keyword search"
    @Published private(set) var embeddedPassages = 0
    @Published var errorMessage: String?
    @Published var showPrivacy = false
    private let engine = RetrievalEngine()
    private var searchTask: Task<Void, Never>?
    private let storageURL: URL
    private var persistenceBlocked = false

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LumaDesk/library.json")
        do {
            documents = try LibraryStore(url: self.storageURL).load()
        } catch {
            persistenceBlocked = true
            errorMessage = "The saved library could not be read. It has not been overwritten. New work is available only for this session until the saved file is repaired or moved. \(error.localizedDescription)"
        }
        Task { await reindex() }
    }

    var selectedHit: SearchHit? { hits.first { $0.id == selectedHitID } }
    var selectedDocument: LibraryDocument? { documents.first { $0.id == selectedDocumentID } }
    var totalPages: Int { documents.reduce(0) { $0 + $1.pages.count } }
    var totalWords: Int { documents.reduce(0) { $0 + $1.wordCount } }

    func chooseFiles() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Add documents to LumaDesk"
        panel.message = "Text is extracted on this Mac and saved in your local library."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .heic, .tiff, .plainText] + ["md", "webp"].compactMap { UTType(filenameExtension: $0) }
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in await self?.importFiles(panel.urls) }
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard !isBusy else { return }
        guard urls.count <= 20 else { errorMessage = "Import up to 20 files at a time."; return }
        isBusy = true
        var failures: [String] = []
        for (index, url) in urls.enumerated() {
            status = "Reading \(index + 1) of \(urls.count) · \(url.lastPathComponent)"
            do {
                let document = try await Task.detached(priority: .userInitiated) { try DocumentImporter.read(url) }.value
                guard documents.reduce(0, { $0 + $1.pages.reduce(0, { $0 + $1.text.count }) }) + document.pages.reduce(0, { $0 + $1.text.count }) <= 2_000_000 else {
                    failures.append("The local library limit is 2 million characters. Remove a source before adding more.")
                    continue
                }
                if documents.contains(where: { $0.title == document.title && $0.pages.map(\.text) == document.pages.map(\.text) }) { continue }
                documents.insert(document, at: 0)
            } catch { failures.append(error.localizedDescription) }
        }
        persist()
        await reindex()
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n\n") }
    }

    func loadSamples() {
        guard !isBusy else { return }
        documents += SampleLibrary.documents.filter { sample in !documents.contains { $0.isSample && $0.title == sample.title } }
        persist()
        Task { await reindex() }
    }

    func remove(_ id: UUID) {
        guard !isBusy else { return }
        invalidateSearch()
        documents.removeAll { $0.id == id }
        if selectedDocumentID == id { selectedDocumentID = nil }
        hits.removeAll { $0.passage.documentID == id }
        persist()
        Task { await reindex() }
    }

    func clearLibrary() {
        guard !isBusy else { return }
        invalidateSearch()
        documents = []; hits = []; selectedDocumentID = nil; selectedHitID = nil
        persist()
        Task { await reindex() }
    }

    func queueSearch() {
        searchTask?.cancel()
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !input.isEmpty else { hits = []; selectedHitID = nil; isSearching = false; return }
        let scope = selectedDocumentID
        isSearching = true
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            let response = await engine.search(input, documentID: scope)
            guard !Task.isCancelled else { return }
            hits = response.hits
            searchMode = response.mode
            if !hits.contains(where: { $0.id == selectedHitID }) { selectedHitID = hits.first?.id }
            isSearching = false
        }
    }

    private func invalidateSearch() {
        searchTask?.cancel()
        hits = []; selectedHitID = nil; isSearching = false
    }

    private func reindex() async {
        invalidateSearch()
        isBusy = true
        status = "Building your local search index…"
        embeddedPassages = await engine.rebuild(documents)
        isBusy = false
        status = documents.isEmpty ? "Ready when you are" : "\(documents.count) sources · Everything stays on this Mac"
        queueSearch()
    }

    private func persist() {
        guard !persistenceBlocked else {
            errorMessage = "This session cannot be saved because the existing library could not be read. Move or repair ~/Library/Application Support/LumaDesk/library.json and relaunch. The original file has not been overwritten."
            return
        }
        do {
            try LibraryStore(url: storageURL).save(documents)
        } catch { errorMessage = "Changes are available this session, but could not be saved: \(error.localizedDescription)" }
    }

    func exportResults() {
        guard !hits.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "LumaDesk-results.md"
        let exported = "# LumaDesk search\n\nQuery: \(query)\nMode: \(searchMode)\n\nRanked source excerpts, not generated answers. Verify OCR against the original.\n\n" + hits.enumerated().map { index, hit in
            "## \(index + 1). \(hit.passage.documentTitle) — page \(hit.passage.page)\n\n\(hit.passage.text)\n\nExtraction: \(hit.passage.extraction)\n"
        }.joined(separator: "\n")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try exported.write(to: url, atomically: true, encoding: .utf8) }
            catch { Task { @MainActor in self?.errorMessage = "Export failed: \(error.localizedDescription)" } }
        }
    }
}

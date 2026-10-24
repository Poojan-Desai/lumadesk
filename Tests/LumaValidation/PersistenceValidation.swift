import Foundation
import LumaCore
import LumaServices

extension ValidationSuite {
    static func runPersistence() -> [ValidationResult] {
        var results: [ValidationResult] = []
        func check(_ name: String, _ condition: Bool) { results.append(ValidationResult(name: name, passed: condition, detail: "")) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumaStore-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(url: folder.appendingPathComponent("library.json"))
        let document = LibraryDocument(title: "Private source", kind: "TXT", pages: [SourcePage(number: 1, text: "Private local text", extraction: "Original text")])
        func rejected(_ documents: [LibraryDocument]) -> Bool {
            do { try LibraryStore.validate(documents); return false } catch { return true }
        }
        do {
            check("A missing library starts empty", try store.load().isEmpty)
            try store.save([document])
            check("Private library persists across reopen", try LibraryStore(url: store.url).load() == [document])
            let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
            check("Library text is owner readable and writable only", permissions?.intValue == 0o600)
            check("Duplicate source identities are rejected", rejected([document, document]))
            let invalidPage = LibraryDocument(title: "Invalid", kind: "PDF", pages: [SourcePage(number: 0, text: "Source", extraction: "PDF text")])
            check("Invalid citation page numbers are rejected", rejected([invalidPage]))
            let duplicatePages = LibraryDocument(title: "Invalid", kind: "PDF", pages: [document.pages[0], document.pages[0]])
            check("Duplicate citation pages are rejected", rejected([duplicatePages]))
            let oversized = LibraryDocument(title: "Large", kind: "TXT", pages: [SourcePage(number: 1, text: String(repeating: "x", count: 250_001), extraction: "Original text")])
            check("Oversized persisted documents are rejected", rejected([oversized]))
            do { try store.save([document, document]); check("Rejected writes preserve the previous library", false) }
            catch { check("Rejected writes preserve the previous library", try store.load() == [document]) }
            try Data("[{broken".utf8).write(to: store.url)
            let damaged = try Data(contentsOf: store.url)
            do { _ = try store.load(); check("Corrupt snapshots are preserved for recovery", false) }
            catch { check("Corrupt snapshots are preserved for recovery", try Data(contentsOf: store.url) == damaged) }
            try JSONEncoder().encode([document, document]).write(to: store.url)
            do { _ = try store.load(); check("Valid JSON with ambiguous source identities is rejected on reopen", false) }
            catch { check("Valid JSON with ambiguous source identities is rejected on reopen", true) }
            try store.save([])
            check("Deletion persists an empty library across reopen", try store.load().isEmpty)
            check("Atomic writes leave no temporary private artifacts", try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["library.json"])
        } catch { results.append(ValidationResult(name: "Private snapshot integration", passed: false, detail: error.localizedDescription)) }
        return results
    }
}

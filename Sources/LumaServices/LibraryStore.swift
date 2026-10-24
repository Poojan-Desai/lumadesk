import Darwin
import Foundation
import LumaCore

/// Validates provenance before either reading or replacing the private snapshot.
/// No original source path is retained; imports remain deliberate snapshots.
public struct LibraryStore: Sendable {
    private static let maximumStorageBytes = 20_000_000
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> [LibraryDocument] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumStorageBytes else { throw LibraryStoreError.invalid("The saved library exceeds the 20 MB storage limit.") }
        let documents = try JSONDecoder().decode([LibraryDocument].self, from: Data(contentsOf: url))
        try Self.validate(documents)
        return documents
    }

    public static func validate(_ documents: [LibraryDocument]) throws {
        var ids = Set<UUID>()
        var libraryCharacters = 0
        for document in documents {
            guard ids.insert(document.id).inserted else { throw LibraryStoreError.invalid("The saved library contains duplicate source identities.") }
            guard !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !document.kind.isEmpty, !document.pages.isEmpty, document.pages.count <= 150 else {
                throw LibraryStoreError.invalid("A saved source has invalid metadata or page count.")
            }
            var pageNumbers = Set<Int>()
            var characters = 0
            for page in document.pages {
                guard page.number > 0, page.number <= 150, pageNumbers.insert(page.number).inserted,
                      !page.extraction.isEmpty else {
                    throw LibraryStoreError.invalid("A saved source has invalid or duplicate page citations.")
                }
                characters += page.text.count
            }
            guard characters > 0, characters <= 250_000 else { throw LibraryStoreError.invalid("A saved source exceeds the supported text limits.") }
            libraryCharacters += characters
            guard libraryCharacters <= 2_000_000 else { throw LibraryStoreError.invalid("The saved library exceeds the 2 million character limit.") }
        }
    }

    public func save(_ documents: [LibraryDocument]) throws {
        try Self.validate(documents)
        let data = try JSONEncoder().encode(documents)
        // Metadata and UTF-8 encoding can exceed the text character limits.
        // Never replace a readable snapshot with one load() would reject.
        guard data.count <= Self.maximumStorageBytes else { throw LibraryStoreError.invalid("The saved library exceeds the 20 MB storage limit.") }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporaryURL = directory.appendingPathComponent(".library-\(UUID().uuidString).tmp")
        // Create with restrictive permissions before writing any private text.
        let descriptor = open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporaryURL) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard rename(temporaryURL.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

public enum LibraryStoreError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

import AppKit
import Foundation
import LumaCore
import PDFKit
import Vision

enum ImportFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum DocumentImporter {
    static let maxCharacters = 250_000
    public static func read(_ url: URL) throws -> LibraryDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ImportFailure.invalid("Choose a document file.") }
        guard (values.fileSize ?? 0) <= 50_000_000 else { throw ImportFailure.invalid("\(url.lastPathComponent) is larger than the 50 MB import limit.") }
        let ext = url.pathExtension.lowercased()
        var pages: [SourcePage] = []
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw ImportFailure.invalid("This PDF is unreadable or password-protected. Unlock it before importing.") }
            guard pdf.pageCount <= 150 else { throw ImportFailure.invalid("This PDF has \(pdf.pageCount) pages. Split it into files of up to 150 pages.") }
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index) else { continue }
                let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !embedded.isEmpty {
                    pages.append(SourcePage(number: index + 1, text: embedded, extraction: "PDF text"))
                } else {
                    let thumbnail = page.thumbnail(of: NSSize(width: 1600, height: 2200), for: .mediaBox)
                    guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                    let text = try recognize(VNImageRequestHandler(cgImage: image))
                    if !text.isEmpty { pages.append(SourcePage(number: index + 1, text: text, extraction: "Vision OCR")) }
                }
                guard pages.reduce(0, { $0 + $1.text.count }) <= maxCharacters else { throw ImportFailure.invalid("This document exceeds the 250,000-character limit. Import a smaller section.") }
            }
        } else if ["txt", "md"].contains(ext) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let text = String(data: data, encoding: .utf8) else { throw ImportFailure.invalid("Save this text file with UTF-8 encoding and try again.") }
            pages = [SourcePage(number: 1, text: text.trimmingCharacters(in: .whitespacesAndNewlines), extraction: "Original text")]
        } else if ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp"].contains(ext) {
            let text = try recognize(VNImageRequestHandler(url: url))
            pages = [SourcePage(number: 1, text: text, extraction: "Vision OCR")]
        } else {
            throw ImportFailure.invalid("Supported formats are PDF, PNG, JPG, HEIC, TIFF, WebP, TXT, and Markdown.")
        }
        let count = pages.reduce(0) { $0 + $1.text.count }
        guard count > 0 else { throw ImportFailure.invalid("No readable text was found in \(url.lastPathComponent). Try a clearer scan or a text-based PDF.") }
        guard count <= maxCharacters else { throw ImportFailure.invalid("This document exceeds the 250,000-character limit. Import a smaller section.") }
        return LibraryDocument(title: url.deletingPathExtension().lastPathComponent, kind: ext.uppercased(), pages: pages)
    }

    private static func recognize(_ handler: VNImageRequestHandler) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

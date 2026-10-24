import AppKit
import Foundation
import LumaCore
import LumaServices
import PDFKit

public struct ValidationResult: Sendable {
    public let name: String
    public let passed: Bool
    public let detail: String
}

/// Shared by XCTest and the Command Line Tools-compatible test executable.
public enum ValidationSuite {
    public static func runCore() -> [ValidationResult] {
        var results: [ValidationResult] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: String = "") {
            results.append(ValidationResult(name: name, passed: condition(), detail: detail))
        }
        check("Empty and whitespace text produce no chunks", TextSegmenter.chunks("  \n\t").isEmpty)
        let chunks = TextSegmenter.chunks("one two three four five six seven", maxWords: 4, overlapWords: 1)
        check("Overlapping segments retain boundary context", chunks == ["one two three four", "four five six seven"])
        check("Nonpositive chunk sizes terminate safely", TextSegmenter.chunks("one two", maxWords: 0, overlapWords: 5) == ["one", "two"])
        let longText = (1...401).map { "word\($0)" }.joined(separator: " ")
        let longChunks = TextSegmenter.chunks(longText)
        check("All words survive segmentation", Set(longChunks.joined(separator: " ").split(separator: " ")) == Set(longText.split(separator: " ")))
        check("Chunks remain bounded", longChunks.allSatisfy { $0.split(separator: " ").count <= 120 })
        check("Unicode normalization retains accented meaning", SearchRanking.tokens("Café CAFÉ; naïve.") == ["cafe", "cafe", "naive"])
        check("Stop words are removed", SearchRanking.tokens("what is the privacy policy") == ["privacy", "policy"])
        check("Identical vector cosine is one", abs((SearchRanking.cosine([1, 2, 3], [1, 2, 3]) ?? 0) - 1) < 0.000001)
        check("Orthogonal vector cosine is zero", SearchRanking.cosine([1, 0], [0, 1]) == 0)
        check("Opposite vectors remain negative", SearchRanking.cosine([1, 0], [-1, 0]) == -1)
        check("Malformed vectors are rejected", SearchRanking.cosine([1], [1, 2]) == nil && SearchRanking.cosine([0], [0]) == nil && SearchRanking.cosine([.nan], [1]) == nil)

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let documents = [LibraryDocument(id: id, title: "Workspace principles", kind: "TXT", pages: [
            SourcePage(number: 3, text: "Private documents are stored on your local device. Privacy starts with local processing.", extraction: "Original text"),
            SourcePage(number: 7, text: "The mountain trail crosses a waterfall and a cedar forest.", extraction: "Vision OCR")
        ])]
        let passages = TextSegmenter.passages(for: documents)
        check("Source page provenance survives chunking", passages.map(\.page) == [3, 7] && passages.allSatisfy { $0.documentID == id })
        check("OCR extraction provenance survives", passages.last?.extraction == "Vision OCR")
        check("Passage identifiers remain stable", passages.map(\.id) == TextSegmenter.passages(for: documents).map(\.id))
        let privacy = SearchRanking.search(query: "local privacy", passages: passages)
        check("Privacy query ranks its relevant source", privacy.first?.passage.page == 3 && privacy.first?.matchedTerms == ["local", "privacy"])
        let hiking = SearchRanking.search(query: "waterfall forest", passages: passages)
        check("A distinct query returns a distinct relevant page", hiking.count == 1 && hiking.first?.passage.page == 7)
        check("Unrelated keywords produce no fabricated match", SearchRanking.search(query: "telescope galaxies", passages: passages).isEmpty)
        check("Empty query produces no results", SearchRanking.search(query: "", passages: passages).isEmpty)
        check("Result limit is enforced", SearchRanking.search(query: "local forest", passages: passages, limit: 1).count == 1)
        check("Nonpositive result limit is safe", SearchRanking.search(query: "local", passages: passages, limit: -3).isEmpty)
        let semantic = SearchRanking.search(query: "confidential", passages: passages, queryVector: [1, 0], vectors: [passages[0].id: [0.99, 0.1], passages[1].id: [0, 1]])
        check("Semantic retrieval finds a nonliteral match", semantic.count == 1 && semantic.first?.passage.page == 3 && semantic.first?.matchedTerms.isEmpty == true)
        let weak = SearchRanking.search(query: "confidential", passages: passages, queryVector: [1, 0], vectors: [passages[0].id: [0.1, 1]])
        check("Weak semantic-only results are filtered", weak.isEmpty)
        check("Keyword matches work without vectors", privacy.first?.semanticSimilarity == nil)
        do {
            let data = try JSONEncoder().encode(documents)
            let restored = try JSONDecoder().decode([LibraryDocument].self, from: data)
            check("Persistence round trip retains complete source content", restored == documents)
        } catch { check("Persistence round trip retains complete source content", false, error.localizedDescription) }
        return results + runEvaluation()
    }

    @MainActor
    public static func runImports() async -> [ValidationResult] {
        var results: [ValidationResult] = []
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            results.append(ValidationResult(name: name, passed: condition, detail: detail))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumaDesk-checks-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { return [ValidationResult(name: "Create synthetic test fixtures", passed: false, detail: error.localizedDescription)] }
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let textURL = folder.appendingPathComponent("Local research.txt")
            try "Documents stay on this device. Privacy matters.".write(to: textURL, atomically: true, encoding: .utf8)
            let document = try DocumentImporter.read(textURL)
            check("UTF-8 text import retains authored content", document.pages.first?.text == "Documents stay on this device. Privacy matters." && document.kind == "TXT")

            let emptyURL = folder.appendingPathComponent("Empty.txt")
            try " \n ".write(to: emptyURL, atomically: true, encoding: .utf8)
            do { _ = try DocumentImporter.read(emptyURL); check("Empty imports are rejected", false) }
            catch { check("Empty imports are rejected", true) }
            let unsupported = folder.appendingPathComponent("Unexpected.csv")
            try "a,b,c".write(to: unsupported, atomically: true, encoding: .utf8)
            do { _ = try DocumentImporter.read(unsupported); check("Unsupported files are rejected", false) }
            catch { check("Unsupported files are rejected", true) }

            let textPDF = folder.appendingPathComponent("Selectable source.pdf")
            let pdfData = NSMutableData()
            var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData), let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw ValidationError.fixture }
            pdfContext.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            ("Local PDF extraction works." as NSString).draw(at: NSPoint(x: 55, y: 670), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            pdfContext.endPDFPage(); pdfContext.closePDF()
            try (pdfData as Data).write(to: textPDF)
            let pdfDocument = try DocumentImporter.read(textPDF)
            check("PDFKit extracts selectable text with page provenance", pdfDocument.pages.first?.text.contains("Local PDF extraction works") == true && pdfDocument.pages.first?.number == 1 && pdfDocument.pages.first?.extraction == "PDF text")

            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 400).fill()
            ("LumaDesk keeps documents private." as NSString).draw(at: NSPoint(x: 45, y: 205), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            ("Search your notes on this Mac." as NSString).draw(at: NSPoint(x: 45, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            let imageURL = folder.appendingPathComponent("Synthetic scan.png")
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ValidationError.fixture }
            try png.write(to: imageURL)
            let imageDocument = try DocumentImporter.read(imageURL)
            check("Vision recognizes synthetic image text locally", imageDocument.pages.first?.text.lowercased().contains("documents private") == true && imageDocument.pages.first?.extraction == "Vision OCR", imageDocument.pages.first?.text ?? "")

            let scannedPDF = PDFDocument()
            let sourceImage = NSImage(size: NSSize(width: 1200, height: 400)); sourceImage.addRepresentation(bitmap)
            guard let imagePage = PDFPage(image: sourceImage) else { throw ValidationError.fixture }
            scannedPDF.insert(imagePage, at: 0)
            let scanURL = folder.appendingPathComponent("Scanned source.pdf")
            guard scannedPDF.write(to: scanURL) else { throw ValidationError.fixture }
            let scanDocument = try DocumentImporter.read(scanURL)
            check("Scanned PDF falls back to Vision OCR", scanDocument.pages.first?.text.lowercased().contains("documents private") == true && scanDocument.pages.first?.extraction == "Vision OCR")

            let engine = RetrievalEngine()
            let count = await engine.rebuild([document, imageDocument])
            let response = await engine.search("documents private", documentID: imageDocument.id)
            check("Retrieval engine obeys document scope", !response.hits.isEmpty && response.hits.allSatisfy { $0.passage.documentID == imageDocument.id }, "Mode: \(response.mode); embedded passages: \(count)")
            let replacement = LibraryDocument(id: document.id, title: document.title, kind: document.kind, pages: [SourcePage(number: 1, text: "この文書は日本語で書かれています。駅から図書館まで歩きます。静かな部屋で本を読みます。", extraction: "Original text")])
            _ = await engine.rebuild([replacement, imageDocument])
            let replaced = await engine.search("private documents", documentID: document.id, mode: .semantic)
            check("Edited passage text invalidates vectors under stable IDs", replaced.eligiblePassages == 1 && replaced.embeddedPassages == 0 && replaced.hits.isEmpty, "Original embedded passages: \(count); replacement is Japanese and excluded from the English semantic index")
            let keywordEngine = RetrievalEngine(semanticEnabled: false)
            _ = await keywordEngine.rebuild([document, imageDocument])
            let coverage = await keywordEngine.coverage()
            check("Disabled semantic index reports zero coverage", coverage.passages == 2 && coverage.embeddedPassages == 0 && !coverage.modelAvailable && coverage.modelRevision == nil && coverage.vectorDimension == nil)
            let fallback = await keywordEngine.search("documents private", documentID: imageDocument.id)
            check("Missing model preserves scoped hybrid keyword retrieval", !fallback.hits.isEmpty && fallback.mode == "Keyword search" && !fallback.queryVectorAvailable && fallback.embeddedPassages == 0 && fallback.eligiblePassages == 1 && fallback.hits.allSatisfy { $0.passage.documentID == imageDocument.id })
            let unavailable = await keywordEngine.search("documents private", documentID: nil, mode: .semantic)
            check("Semantic baseline never silently substitutes keywords", unavailable.hits.isEmpty && unavailable.mode == "Semantic unavailable")
            let bm25 = await keywordEngine.search("documents private", documentID: nil, mode: .bm25, limit: 1)
            check("Engine exposes bounded pure BM25 without query vectors", bm25.hits.count == 1 && bm25.mode == "BM25 only" && !bm25.queryVectorAvailable)
            _ = await engine.rebuild([])
            let removed = await engine.search("documents", documentID: nil)
            check("Removing sources clears searchable index", removed.hits.isEmpty)
        } catch {
            results.append(ValidationResult(name: "Synthetic import integration suite", passed: false, detail: error.localizedDescription))
        }
        return results
    }
}

private enum ValidationError: Error { case fixture }

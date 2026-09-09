# LumaDesk

**Find the thought you saved. Keep the source in sight.**

A native macOS document workspace built with SwiftUI, AppKit, Vision, PDFKit, and NaturalLanguage. Import your notes, PDFs, or scans, search for an idea, and inspect relevant passages with their original source and page. All document processing happens on your Mac.

This is a functional portfolio MVP, with no account, hosted backend, API key, telemetry, external package dependency, or model-service bill. Its AI features are local OCR and semantic retrieval. It **does not generate conversational answers** or claim that relevance measures correctness.

[Preview release v0.1.0](https://github.com/Poojan-Desai/lumadesk/releases/tag/v0.1.0) · [Source code](Sources) · [Native macOS CI](https://github.com/Poojan-Desai/lumadesk/actions/workflows/ci.yml) · [Demo walkthrough](PORTFOLIO.md)

## Engineering highlights

- **Native macOS product:** SwiftUI and AppKit workspace with PDFKit text extraction, Vision OCR, and Markdown export with source/page citations.
- **Local information retrieval:** BM25 keyword ranking combined with NaturalLanguage sentence embeddings and cosine similarity; keyword search remains available when semantic search is unavailable.
- **Responsive architecture:** actor-isolated retrieval, OCR and embedding work off the main actor, and debounced, cancellation-aware search presentation.
- **Verification:** 32 shared validation assertions covering ranking, provenance, persistence, document import, and real OCR fixtures. [GitHub CI passed](https://github.com/Poojan-Desai/lumadesk/actions/runs/34150903363) for the preview source revision; the workflow link above shows current status.

**Release status:** v0.1.0 is a portfolio preview for Apple silicon and macOS 14+. The downloadable app has an ad-hoc signature; it is not Developer ID signed or notarized. See [build instructions](#build-a-launchable-app) for the reproducible source build and distribution limitations.

## Quick start

Requirements: macOS 14 or newer; Swift 5.10 or newer; Apple Command Line Tools or Xcode. The provided binary is built for Apple silicon. Intel users can build from source on an Intel Mac.

```sh
swift build
swift run LumaDesk
```

In the app, choose **Try sample library**, then search **Where is my data stored?**. Select a result to inspect its passage and page. Press **⌘O** to import a file, **⌘F** to focus search, or **⇧⌘E** to export all current results as Markdown. The sample library contains original, synthetic demonstration text.

The app is intentionally a local workspace, not a server. No backend or network setup is needed.

## Run the checks

```sh
# Works with Command Line Tools alone; exits nonzero on any failure.
swift run LumaDeskChecks

# Runs the same shared validation suite when full Xcode/XCTest is installed.
swift test
```

The shared suite performs 32 assertions covering segmentation boundaries and malformed parameters; Unicode token normalization; BM25 and semantic ranking; invalid vectors and empty queries; stable source/page provenance; JSON round trips; actual UTF-8/PDF import; actual Vision OCR on synthetic image and scanned-PDF fixtures; document-scoped retrieval; and deleted-source index removal. It never reads personal documents. Temporary generated fixtures are removed afterward.

On the development Mac, all **32/32 checks passed**, including real local embeddings and OCR. `swift test` was also attempted, but this machine's Command Line Tools installation lacks XCTest (`error: XCTest not available`). The standalone executable runs the same validation code and passed. This is an environment limitation, not a claim that XCTest ran.

## Build a launchable app

```sh
bash scripts/package-app.sh
open dist/LumaDesk.app
```

An optional first argument chooses the destination directory:

```sh
bash scripts/package-app.sh /absolute/path/to/deliverables
```

The script builds a release executable, renders the app icon, creates the `.app` bundle, applies an ad-hoc code signature, verifies it, and creates `LumaDesk-macOS.zip`. **This preview is not Developer ID signed or notarized.** Local launch works on the build Mac; a downloaded build on another Mac may be blocked by Gatekeeper. Building from source is the reproducible preview route. Production distribution would require Apple signing, notarization, and a distribution review.

## How search works

1. A deliberate file picker action grants access to the chosen files. No folder scanning, background monitoring, or clipboard reading occurs.
2. PDFKit extracts selectable PDF text. Image-only PDF pages and supported images are read by Vision OCR.
3. Text is split into passages of at most 120 words with 20 words of overlap. Each passage retains its document ID, source title, page, and extraction method.
4. NaturalLanguage's on-device English sentence embedding model creates passage vectors when it is available. Language recognition keeps non-English passages out of the English semantic index.
5. Search combines BM25 keyword relevance (60%) and cosine similarity (40%) when the query and source have vectors. Keyword ranking works independently. Semantic-only matches need at least 0.55 cosine similarity; this is a product heuristic, not a calibrated accuracy threshold.
6. The app presents up to 12 ranked source excerpts, with provenance and an explanation of matched words or semantic relatedness. Export retains those citations.

The interface explicitly reports **Semantic + keyword** or **Keyword search** for the current query. Model availability and language support vary. The app does not download a model itself or initiate network requests.

## Privacy and retention

- Only explicitly selected files are processed. Original file paths are not persisted, and original files are not copied into the library.
- Extracted text and document metadata are saved in `~/Library/Application Support/LumaDesk/library.json`. That content can be sensitive. It is not encrypted by the app; your Mac account and optional FileVault provide operating-system protection.
- Removing a source removes its extracted text from the current library and search index. Removing all sources writes an empty library. This does not securely erase disk sectors or remove operating-system backups.
- Exported Markdown contains the selected query and matching source text. It is written only after a user-triggered save dialog. Copying a citation writes only the selected passage to the clipboard after an explicit click.
- There is no networking implementation, analytics SDK, cloud model, account, or external dependency in this project.
- The local preview is not App Sandbox-enabled. The file picker is a deliberate-access product boundary, not an OS sandbox boundary. App Store distribution should add sandbox entitlements and review persistence behavior.

## Limits

- PDF, PNG, JPG/JPEG, HEIC, TIFF, WebP, UTF-8 TXT, and Markdown. A multi-frame image imports only the frame handled by Vision; use PDF for multi-page scans.
- Up to 20 files per import, 50 MB per file, 150 PDF pages, 250,000 extracted characters per document, and 2 million extracted characters per library. These bounds keep the prototype manageable; this is not a large-corpus engine.
- English semantic search only. Other text uses Unicode-aware keyword matching; stop-word filtering is English. Very short queries may be language-detected unexpectedly and use the keyword fallback.
- OCR can miss or misread text. A PDF with embedded text uses that text and does not also OCR images on the same page; image annotations in mixed pages may therefore be absent.
- Search surfaces excerpts; it is not a question-answering language model. It can miss or misrank results and cannot establish source truth. Embeddings remain in memory and are rebuilt at launch.
- The local store is a single atomic JSON file. If it cannot be decoded, the app preserves it and blocks saving rather than overwriting it. Move or repair the file, then relaunch, to restore persistence.
- Keyboard navigation, labels, selection, and native controls are implemented. VoiceOver, localization, performance on large collections, signing, and security hardening still need broader production testing.

## Architecture

```text
SwiftUI workspace + AppKit file/save panels
    │
    ├── WorkspaceModel (@MainActor)
    │      ├── Atomic local JSON persistence
    │      └── Debounced, cancellation-aware search presentation
    │
    ├── LumaServices
    │      ├── DocumentImporter → PDFKit / Vision (detached task)
    │      └── RetrievalEngine actor → NaturalLanguage + index
    │
    └── LumaCore
           ├── Codable/Sendable document and source-page models
           ├── Bounded overlapping text segmentation
           └── Deterministic BM25 + cosine ranking
```

`LumaCore` owns deterministic models and ranking. `LumaServices` owns Apple-framework integrations and the actor-isolated semantic index. The UI does not perform OCR or embedding work on its main actor. `LumaValidation` is a shared test fixture suite used by both XCTest and the dependency-free check executable.

## Portfolio discussion

This project demonstrates native interaction design, Apple ML framework integration, explicit provenance, pragmatic privacy decisions, actor isolation, graceful model fallback, and verification against generated real file fixtures. See [PORTFOLIO.md](PORTFOLIO.md) for a short demo and an honest engineering discussion. No affiliation with or endorsement by Apple is claimed.

## License

MIT. See [LICENSE](LICENSE).

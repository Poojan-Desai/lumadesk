# LumaDesk

A native macOS workspace for searching notes, PDFs, and scans with source and page citations. Built with **SwiftUI, AppKit, PDFKit, Vision, and NaturalLanguage**, with no external package dependencies or hosted backend.

[Source](Sources) · [CI](https://github.com/Poojan-Desai/lumadesk/actions/workflows/ci.yml) · [Demo walkthrough](PORTFOLIO.md) · [Retrieval evaluation](BENCHMARK.md)

## What it does

- Extracts selectable PDF text and uses on-device Vision OCR for scans and images.
- Combines BM25 keyword ranking with English sentence embeddings and cosine similarity; keyword search works when the local model is unavailable.
- Keeps source/page/extraction provenance through search and Markdown export.
- Runs retrieval in an actor, performs OCR off the main actor, and cancels superseded search presentation.
- Invalidates cached vectors when passage text changes, including edits that retain the same passage ID.
- Saves validated snapshots using an owner-only temporary file and atomic replacement. Duplicate source/page identities, damaged data, and oversized snapshots cannot replace a readable library.

This is a portfolio preview that retrieves excerpts. It does not generate answers or treat relevance scores as factual confidence.

## Run

Requires **macOS 14+**, **Swift 5.10+**, and Apple Command Line Tools or Xcode.

```sh
swift build
swift run LumaDesk
```

Choose **Try sample library**, then search **Where is my data stored?**. Use **⌘O** to import, **⌘F** to search, and **⇧⌘E** to export results. Samples and test documents are original synthetic fixtures.

To create a launchable application:

```sh
bash scripts/package-app.sh
open dist/LumaDesk.app
```

The packaged preview uses an ad-hoc signature; it is not Developer ID signed or notarized. The existing [v0.1.0 release](https://github.com/Poojan-Desai/lumadesk/releases/tag/v0.1.0) predates the October reliability and benchmark work. Build the current source to use those changes.

## Verification

```sh
swift run LumaDeskChecks
swift build --product LumaBenchmark
python3 scripts/check-benchmark.py
swift test  # Requires a full Xcode installation with XCTest.
```

Local verification on **October 28, 2026** passed **73 shared validation assertions and 22 benchmark CLI checks**. Coverage includes real PDF extraction and Vision OCR, local embeddings, stale-vector invalidation, citation refresh, document scope, private persistence, corrupted/oversized snapshot preservation, hand-calculated retrieval metrics, and missing-model behavior. A release build of the application also passed. `swift test` could not run on this Command Line Tools installation because XCTest is unavailable; the standalone executable runs the same shared validation suite. The CI link above reports remote results separately.

The benchmark compares isolated BM25, isolated cosine, and the app's hybrid ranker on **16 synthetic documents and 15 queries**. Reports retain Recall@5, graded NDCG@5, timing samples, embedding coverage, hardware/model metadata, and the corpus SHA-256. Undefined semantic scores remain absent when the model is unavailable. These small, author-judged fixtures validate the evaluation pipeline; they do not establish representative search quality. See [BENCHMARK.md](BENCHMARK.md) for reproducible commands, raw reports, and limitations.

## Architecture

```text
SwiftUI / AppKit workspace
  ├── WorkspaceModel: local persistence and cancellation-aware presentation
  ├── LumaServices: PDFKit / Vision import, private LibraryStore, retrieval actor
  └── LumaCore: source models, text segmentation, BM25 / cosine, evaluation metrics
```

Passages use 120-word windows with 20-word overlap. Hybrid ranking combines lexical relevance (60%) and cosine similarity (40%) when vectors exist, with a 0.55 threshold for semantic-only matches. English semantic support depends on the installed NaturalLanguage model; other text uses Unicode-aware keyword matching.

## Privacy and limits

- Files are processed only after explicit selection. No networking, account, telemetry, model-service API, or background folder scanning is implemented.
- Extracted text is stored at `~/Library/Application Support/LumaDesk/library.json`. Original file paths are not retained. Snapshots use owner-only file permissions but are not encrypted by the app.
- Imports are snapshots: changing an original file requires importing it again. Removing a source clears it from the saved library and index, without securely erasing disk sectors or backups.
- Supports PDF, PNG, JPG/JPEG, HEIC, TIFF, WebP, UTF-8 TXT, and Markdown. Limits: 20 files per import, 50 MB per file, 150 PDF pages, 250,000 characters per source, and 2 million characters per library.
- OCR and ranking can miss information. PDFs with embedded text do not also OCR images on that page. Embeddings stay in memory and rebuild at launch.
- The preview is not App Sandbox-enabled. Broader accessibility testing, large-corpus evaluation, signing, and notarization remain production work.

For persistence safeguards and engineering decisions, see [October hardening notes](docs/HARDENING-2026-10.md). MIT license; see [LICENSE](LICENSE).

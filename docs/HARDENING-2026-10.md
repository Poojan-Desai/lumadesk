# Local snapshot and citation hardening — October 24, 2026

## Story 1: Make damaged structured data recoverable

The original app preserved undecodable JSON, but successfully decoded records bypassed invariants that imported documents normally satisfy. Duplicate source UUIDs or duplicate page numbers can produce identical stable passage IDs and ambiguous source citations. A single shared LibraryStore now validates those invariants before loading and before saving. It bounds document/page/library text, source identity, and positive page provenance. It preserves the existing Codable schema and does not persist original file paths.

Private text is written into a unique sibling temporary file created with mode 0600 before any content is written. The file is synchronized and atomically renamed into place; newly created library directories use mode 0700. Validation occurs before opening a replacement. Tests demonstrate that invalid writes leave the prior library readable, that bad JSON is preserved on failed load, and that save/reopen/deletion leave no temporary artifacts. This is owner-only storage and atomic replacement, not app-level encryption, secure erasure, or a guarantee against every power-loss filesystem scenario.

## Story 2: Keep source mutations and search presentation aligned

The local baseline already invalidates passage vectors when text changes under stable IDs. The presentation layer still allowed a debounced or in-flight old search to finish while removal/index rebuild was pending. The model now cancels search presentation and clears selected hits before source removal or rebuilding. Searches submitted while the index is busy are discarded; the final rebuild queues the current query again. This prevents stale pending presentation from restoring deleted citations.

A real engine regression renames the source, reorders the page content, and changes extraction to revised OCR while preserving the document identity. The returned passage has the new title, correct new page, and updated extraction provenance. Deleted sources disappear from the index. The UI race fix was compiled with the app; the actor citation behavior has automated coverage. A dedicated automated UI scheduling harness is not present, so the exact UI interleaving is not claimed as end-to-end tested.

## Architecture

```text
Explicit import -> document snapshots -> WorkspaceModel
                         |                    |
                         v                    v
                  LibraryStore          RetrievalEngine actor
             validate -> 0600 temp      text-aware vector cache
                  -> sync -> rename     -> source/page hits
```

## Verification

- Baseline: 59/59 shared assertions.
- Current: 72/72 shared assertions, including real PDFKit and Vision OCR fixtures, retrieval, file persistence and citations.
- Benchmark CLI: 22/22 checks; full native LumaDesk and release benchmark build pass.
- `swift test` was attempted. The active `/Library/Developer/CommandLineTools` installation has no XCTest platform; it reports `error: XCTest not available`. No Xcode app is installed. The same shared assertion code passed through LumaDeskChecks.
- Release retrieval rerun: original synthetic CC0 fixture, 16 documents, 17 passages, 13 judged queries plus 2 controls, five repetitions/one warmup. Apple M3 Pro / Mac15,6 / 18 GiB / macOS 14.4 arm64. BM25 Recall@5 1.0000 and NDCG@5 0.9928; cosine 0.9615 / 0.8769; hybrid 1.0000 / 1.0000. These are fixture diagnostics, not general search-quality or improvement claims. New raw timings and hardware/RSS are supplied in the evidence report.

## Demo

Run `swift run LumaDesk`, choose Try sample library, search for privacy and inspect the page/extraction label. Remove that source; its result disappears. Run `swift run LumaDeskChecks` to reproduce the malformed snapshot/reopen/citation mutation fixtures without reading personal documents. Tests create and remove temporary original synthetic fixtures.

## Limits and unfinished directive work

No automatic watching of external changes, rename, deletion, or relocation exists. Import creates a snapshot and intentionally forgets its path. A deliberate reimport is a separate source unless its existing title and extracted text match. There is no source-refresh UI, benchmark corpus expansion, import cancellation/progress redesign, security-scoped bookmark persistence, app sandbox, or broad accessibility certification. BM25/cosine/hybrid benchmarking already existed in the baseline; this increment reruns it without claiming a performance optimization. No signed/notarized distribution or remote release was attempted.

# LumaDesk: portfolio case study

**Problem:** Important ideas are scattered across notes, PDFs, and scans. Finding the relevant passage often requires remembering exact words or uploading private material.

**Outcome:** A native macOS workspace that combines local text recognition and semantic retrieval, then returns directly inspectable evidence with source/page provenance.

## A 90-second demo

1. Launch LumaDesk and load the original sample library.
2. Search “Where is my data stored?” Show the retrieval mode, ranked passages, and source page.
3. Select a result. Explain the difference between retrieval relevance and answer accuracy.
4. Import a clearly readable image containing test text. Explain how Vision converts the scan into searchable text without an external service.
5. Copy a citation or export search results. Remove the imported source, then show that it is no longer searchable.
6. Open Privacy & Local AI to show the exact retention and fallback behavior.

## Engineering choices worth discussing

| Choice | Benefit | Tradeoff |
| --- | --- | --- |
| Native SwiftUI and AppKit | Platform conventions, keyboard commands, text selection, accessible controls | macOS-only product |
| Vision and PDFKit extraction | Real scans and text PDFs work locally | OCR errors and mixed-page limitations |
| NaturalLanguage sentence embeddings | Semantic retrieval with no API key or service cost | English model availability varies by Mac |
| Hybrid BM25 and cosine ranking | Exact terms remain useful alongside related ideas | Weights and similarity floor need corpus evaluation |
| Original excerpts and page provenance | Users can inspect the evidence behind a match | No synthesized conversational answer |
| Retrieval actor and detached import | OCR/index work stays off the main UI actor | Prototype indexing is sequential |
| Atomic JSON store and bounded imports | Simple, inspectable local persistence | A production-scale library needs a database and incremental indexing |

## Verification

The shared validation suite runs 59 assertions against generated PDFs and images through PDFKit and Vision, deterministic ranking, hand-calculated retrieval metrics, unavailable-model fallback, and stale-vector invalidation after text changes. A further 22 CLI checks verify reports, argument handling, deterministic BM25, and candidate coverage when one document has many passages. The benchmark compares BM25, cosine, and hybrid modes on 16 original synthetic documents and 15 queries, with hardware and model coverage recorded. These are engineering regression fixtures, not representative accuracy evidence; see [BENCHMARK.md](BENCHMARK.md). Full VoiceOver, latency benchmarks across hardware, representative public-corpus evaluation, and production security review remain future work.

## Next milestones

1. Extend the existing Recall@5/NDCG@5 harness with a licensed, representative corpus and independent judgments before tuning ranking weights.
2. Add mixed-page image OCR and searchable bounding boxes for visual source highlighting.
3. Move library storage to a versioned database with incremental index updates.
4. Add App Sandbox entitlements, Developer ID signing, notarization, and a reproducible release workflow.
5. Run VoiceOver and high-contrast usability sessions; localize the interface.

This is a demonstrable MVP and a starting point for an engineering conversation, not a claim of production maturity or a guarantee of hiring outcomes.

# Portfolio review — November 7, 2026

Base: `0b60d4bdbeda09730f280141b2c578568495b89d`.
Local review branch: `codex/portfolio-audit-2026-11-07`. Changes are proposed
source, with a downloadable patch; this review does not publish a new release.

## Before and after

Previously, each search retokenized every eligible passage and reconstructed its
term counts. The retrieval engine also ran language recognition for pure BM25 and
missing-model searches even though they could not consume a semantic vector.
`LexicalSearchIndex` now stores passage term frequencies and lengths once per
library rebuild. Scoped BM25 document frequency and average length remain scoped,
and ranking weights, semantic gates, normalization, tie ordering and citations
are preserved. The engine rebuilds this immutable index on every library change,
so edits retaining passage IDs cannot reuse old lexical text. Query language
recognition runs only when the requested mode can actually use an embedding.

Tradeoff: additional resident term-count dictionaries and extra index-build work.
This is not an incremental or inverted index; queries still visit eligible
passages, and embedding computation is unchanged.

## Fresh verification

- Baseline `swift run LumaDeskChecks`: **83/83** assertions passed.
- Candidate `swift run LumaDeskChecks`: **92/92** passed. Nine new assertions cover
  a hand-calculated scoped BM25 score, scoped corpus normalization, repeatability,
  missing scope, changed text under stable IDs, updated citations, semantic
  admission, empty/limited queries, and the actual engine's stale lexical cache.
- `python3 scripts/check-benchmark.py .build/release/LumaBenchmark`: **22/22**.
- `python3 scripts/check-package.py`: **24/24**, isolated tool doubles; these do
  not validate Apple signing or notarization.
- `swift build -c release --product LumaDesk`: passed.
- `swift test`: attempted, exits 1 with **XCTest not available** on this Mac's
  Command Line Tools. Shared executable assertions ran successfully. Remote CI
  was not triggered and native SwiftUI interactions were not automated here.

## Paired measurements

Release binaries from the base commit and candidate ran on the same Mac15,6,
Apple M3 Pro, arm64, macOS 14.4 (23E214), Swift 5.10. The unchanged CC0 authored
fixture has 16 documents, 17 passages, 15 queries including two controls, and 13
positively judged queries. Corpus SHA-256:
`ad93b9d0a99312cbad19c8f4a70cee565b302adc2dbc8c8231929765358295eb`.

Pure BM25, semantics disabled, 100 measured repetitions per query after 3 warmups:

| Trial | Baseline median ms | Candidate median ms | Baseline P95 ms | Candidate P95 ms |
|---|---:|---:|---:|---:|
| 1 | 2.137875 | 0.030541 | 2.541083 | 0.037583 |
| 2 | 2.087541 | 0.030750 | 2.473792 | 0.037625 |

Trial 2 has a 98.53% lower measured median engine latency. Trial 2 index time
increased from 0.746 to 1.295 ms; no memory improvement is claimed. The reports
contain all 1,500 timing samples per trial, including the empty-query control.
This fixed small workload is not a throughput/load test or representative user
study. The baseline repeatedly performs language detection; avoiding that work
accounts for much of the keyword-only benefit. Do not claim the whole application
is 98.5% faster: the UI intentionally waits 220 ms before searching, and ordinary
semantic queries still compute a sentence embedding.

Fresh all-mode reports (5 repetitions, one warmup) preserve **45/45** per-query
mode top-five document rankings and Recall@5/NDCG@5 values. BM25 macro Recall@5
is 1.0 and NDCG@5 is 0.992822; semantic is 0.961538/0.876886; hybrid is 1.0/1.0.
The same quality values existed before this optimization. They are plumbing
regressions on authored fixtures, not an independently validated quality gain.
The 15-query all-mode timing run is diagnostic and is not used to claim a general
semantic latency improvement.

## Reproduce

Build the base and candidate in separate clean checkouts. For each:

```sh
swift build -c release --product LumaBenchmark
.build/release/LumaBenchmark --disable-semantics --mode bm25 --repetitions 100 --warmups 3 --output bm25.json
.build/release/LumaBenchmark --repetitions 5 --warmups 1 --output all-modes.json
```

Run both on the same Mac with the same corpus hash and compare matching query IDs,
ranked document IDs, quality fields, build configuration, model coverage and
hardware metadata. Timing includes engine actor dispatch and ranking, and query
embedding when used; it excludes UI debounce and rendering. Raw reports are in
`Benchmarks/keyword-cache-2026-11-07/`. Report order was baseline, candidate,
baseline repeat, candidate repeat; load was not isolated and no statistical
confidence interval is claimed. The benchmark does not read the saved library.

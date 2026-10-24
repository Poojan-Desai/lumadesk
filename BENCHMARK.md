# Retrieval evaluation

`LumaBenchmark` evaluates the same ranking implementation used by the app, plus isolated BM25 and cosine baselines. It measures retrieval of source documents, not generated-answer accuracy. It reads only the bundled fixture or an explicitly supplied JSON file and never accesses the user's saved library.

## Reproduce

Requires macOS 14+, Swift 5.10+, and Command Line Tools or Xcode. No external package is needed. Use release builds for timing comparisons:

```sh
swift build -c release --product LumaBenchmark
.build/release/LumaBenchmark --repetitions 5 --warmups 1 --output benchmark-report.json
.build/release/LumaBenchmark --disable-semantics --repetitions 5 --warmups 1 --output benchmark-no-model.json

# Optional independent mode or licensed custom corpus.
.build/release/LumaBenchmark --mode bm25 --corpus /absolute/path/corpus.json
.build/release/LumaBenchmark --help
```

The default [CC0 fixture](Sources/LumaBenchmark/Fixtures/english-v1.json) contains 16 original synthetic English documents, 17 passages, 13 positively judged queries, one out-of-domain no-answer control, and one whitespace control. Judgments are manually authored by the fixture author; unlisted documents are grade zero. This small corpus exercises the evaluation pipeline. It is not independently judged, held out, or representative of user search traffic. No ranking parameters were tuned against it, and its scores do not establish general search quality.

## Scoring contract

- Rank every eligible passage, deduplicate documents by first appearance, then take five documents. A long document cannot consume the top-five document candidate pool through repeated passages.
- Recall@5 is retrieved positive documents divided by all positive documents judged for that query.
- NDCG@5 uses gain `2^grade - 1`, discount `log2(rank + 1)`, and the ideal top five from all positive judgments. Grades are 0–3.
- Report macro means over positively judged, available queries only. A judged query with no hits scores zero. No-positive queries and unavailable semantic queries have quality fields omitted, and their counts/statuses remain visible.
- No-answer controls are diagnostic examples, not abstention-accuracy measurements. Inspect their returned IDs separately; they never inflate quality means.
- Baseline BM25 uses raw BM25 (`k1=1.2`, `b=0.75`) with lexical matches only. Pure cosine ranks all valid query/passage vectors, including negative similarity, with no product threshold or lexical gate. Hybrid preserves the app's original 60/40 weighting and 0.55 semantic-only admission threshold.
- Missing query vectors or zero embedded passages make the semantic baseline unavailable. Hybrid explicitly reports keyword fallback. Compare mode means only when evaluated query IDs and coverage match; partial semantic coverage changes the evaluation cohort.

## Measurements and provenance

JSON contains a schema version, exact corpus SHA-256, corpus license/provenance, OS and hardware, model revision/dimension, embedding coverage, per-query document IDs, and raw timing samples. Query latency includes actor dispatch, query embedding, and ranking after configured warmups; segmentation and passage embedding are measured separately as index time. Model initialization has its own duration. Median and P95 use the nearest-rank method. Peak RSS is Darwin's whole-process lifetime high-water mark in bytes, shared across all sequential modes; it is not per-mode memory use. Release/debug configuration and repetitions are recorded.

Model availability, NaturalLanguage model revisions, language recognition, CPU load, and hardware can change results. The benchmark does not download a model. `--disable-semantics` provides a reproducible missing-model path and verifies that a semantic baseline never silently becomes a keyword baseline. Local example reports are in [Benchmarks](Benchmarks); rerun on your target Mac before drawing performance conclusions.

Local release-build example, October 24, 2026: Apple M3 Pro (`Mac15,6`, arm64), English sentence embedding revision 1, 512 dimensions, all 17 passages embedded, five measured repetitions after one warmup per query. Quality means use the same 13 positive queries; latency summaries include all 15 queries and therefore include the empty-query control.

| Mode | Recall@5 | NDCG@5 | Median query ms | P95 query ms |
| --- | ---: | ---: | ---: | ---: |
| BM25 | 1.0000 | 0.9928 | 1.603 | 2.212 |
| Cosine | 0.9615 | 0.8769 | 6.394 | 7.383 |
| Hybrid | 1.0000 | 1.0000 | 6.224 | 7.204 |

These fixture scores are not measured improvements over a prior version. The [disabled-model report](Benchmarks/disabled-model-macos-2026-10-24.json) marks semantic mode unavailable and records 15/15 hybrid keyword fallbacks, with no semantic quality means. [Raw local-model results](Benchmarks/local-model-macos-2026-10-24.json) retain every query, ranking, timing sample, and environment field. Corpus SHA-256: `ad93b9d0a99312cbad19c8f4a70cee565b302adc2dbc8c8231929765358295eb`.

## Regression coverage and CI

`swift run LumaDeskChecks` runs the shared 72-check suite, including golden metric calculations, deduplication, baseline separation, corpus validation, real PDF/OCR imports, scoped fallback, and stale-vector invalidation when text changes under a stable passage ID. The same suite is invoked by XCTest on full Xcode installations. `python3 scripts/check-benchmark.py` runs 22 black-box CLI checks with only Python's standard library, including exact corpus checksums, missing-model reports, invalid inputs, deterministic BM25 rankings, and long-document candidate exhaustion.

The native macOS workflow runs these checks and uploads a short local-model report. There is deliberately no quality or latency pass threshold for this small fixture. A future quality gate needs a licensed representative corpus, independent judgments, a held-out set, and a defined hardware/model baseline.

## Custom corpus

Use schema `lumadesk-evaluation/v1` and the bundled JSON structure. Required fields are a name, provenance, license, 1–500 uniquely identified UUID documents with nonempty titled pages, and 1–200 uniquely named queries. Page numbers must be positive and unique per document. Each query maps corpus document UUIDs to integer grades 0–3. Blank query text and empty judgments are allowed as explicit controls. Limits are 500 query characters, two million document characters, and five MB of input JSON. Invalid corpus data or options exit nonzero without writing a report.

# Native preview review — November 2, 2026

Reviewed from `8c108e8`. The October source already implemented on-device PDF
extraction/OCR, hybrid retrieval, cache invalidation, citation refresh and private
validated atomic library snapshots. This follow-up fixes stale presentation and
clean packaging; it does not add a cloud service or generated answers.

## Changes and verification

- New query/scope input synchronously clears prior hits before debounce. Request
  identities reject superseded responses even for repeated query text. Exports
  require a completed matching query/scope and capture that result context.
  Imports invalidate prior presentation immediately.
- Ten shared-state regression assertions bring `LumaDeskChecks` to **83/83**.
  PDFKit extraction, actual Vision OCR, local embeddings, source/page citations,
  changed-text caches, corrupted and oversized snapshot preservation still pass.
- **22/22 benchmark CLI checks** pass. A fresh three-repetition authored-fixture
  report used 16 documents/15 queries, with 17/17 passages embedded in semantic
  and hybrid modes. This fixture checks evaluation plumbing, not general search
  quality or factual accuracy. Ranking scores are not confidence scores.
- Debug and release app builds pass. `swift test` was attempted and reports
  `XCTest not available` with this Mac's Command Line Tools. The shared standalone
  suite ran locally; the macOS GitHub Actions workflow runs XCTest separately.
- `--demo` uses only three original sample documents in memory, bypasses normal
  saved-library load/save, and disables imports. Native UI checks verified a
  privacy query with page 2 citation, a changed waterfall query with page 1
  citation, exact Markdown query/source/extraction content, scope filtering to
  zero results, and no export panel for empty scoped results.
- **24 isolated packaging checks** cover stale-resource exclusion, repeated
  packaging, failure preservation/restore and destination locking. Real native
  packaging also passed property-list validation and strict signature verification.
  Only the compiled binary, generated icon and explicit Info.plist enter the app.

## Packaging and distribution boundary

Packages are assembled in a fresh owned staging directory. Build/sign/archive
completion precedes output replacement. A destination lock prevents overlapping
package publication; rename failures attempt restoration and retain backups if
restoration fails. This is not a power-loss transaction.

The source preview identifies version 0.2.0, source commit and clean/modified or
unavailable provenance. The locally built binary is **arm64**, macOS 14+, with an
**ad-hoc signature**, **no TeamIdentifier**, and **no Developer ID notarization**.
Strict `codesign` verification passed; `spctl --assess` rejected it as expected.
Do not describe it as a production-signed app. No Gatekeeper setting was changed.
Build from source or use a clearly labeled preview; production distribution still
requires appropriate Apple signing credentials, hardened runtime review and
notarization. The old v0.1.0 release is historical.

No third-party Swift packages, networking, telemetry, private documents or source
file paths are bundled. Owner-only persisted text is not app-level encryption;
OCR can err, imports are snapshots, and the preview is not App Sandbox-enabled.

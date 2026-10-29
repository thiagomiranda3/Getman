# Audit fixes — 2026-10-13

User-approved scope: fix all five confirmed defects and the CSV/decompression performance opportunities from the preceding audit. Preserve existing user edits and Hive schemas. All SDK commands use FVM.

## Implementation groups

1. Network: add redirect origin regressions; strip credentials on scheme/host/port changes. Bound native decompression while retaining malformed/already-decoded behavior and web safety. Owner: network_fixes.
2. Response performance: replace quadratic-memory diff, bound work, move response comparison off the UI isolate, cache bounded CSV parsing off-isolate. Cover identical/many-line inputs and widget replacement/disposal. Owner: response_performance.
3. Chaining: reproduce stale rule completion and repeated captures. Keep per-send cancellation identity through rule evaluation; reject stale completions; reset capture deduplication when a new run clears its results. Cover cancellation, closed/reopened tabs, and subsequent sends. Owner: root.
4. History: reproduce simultaneous duplicate writes. Serialize add/delete/clear/undo operations with a failure-resilient queue; verify ordering, dedup, trim, and recovery. Owner: root.
5. Integration: update architecture/CODEMAP as necessary and feature wiki for changed visible behavior/limits. Review combined changes. Run flutter analyze, custom_lint, lint fixtures, bloc_lint, formatter, and full Flutter tests.

## Verification

First make focused regressions fail for the reported reason, then implement and run the related suites. Avoid timing assertions in regression tests; rerun the audit benchmark separately. Full baseline from the audit: 3674 tests green, all four static checks clean, 835 files format-clean. No Hive model change is planned.

## Progress

- Groups 1–4 implemented; focused suites passed (195 network, 44 response, 85 state tests).
- Final integration pass: 3718 tests passed; all four static-analysis passes clean;
  formatter reported 838 files with no changes.
- Final review found a cancellation window during asynchronous decompression and
  pending rules. The consolidated correction passed four deterministic red/green
  regressions, 348 related tests, and the final scoped review.
- Feature wiki updates published to master in commit `7538ece`.
- Decision: diff uses a fixed 1,000,000-cell uint32 work budget (~4 MB), with
  summary-only fallback for excessive complexity. This intentionally trades
  exhaustive diffs on pathological inputs for bounded resource usage; the UI
  message and wiki explain the limit.

# Testing conventions — how bugs get past 94% coverage, and the rules that stop them

> Loaded on demand — see the routing table in CLAUDE.md. Read this BEFORE
> writing or reviewing any widget/bloc test. These rules exist because each
> one maps to a real shipped bug that the suite already "covered" — the test
> executed the buggy lines and passed anyway.

## Why coverage % does not protect you

Line coverage measures *execution*, not *assertion strength*. A test can run
100% of a widget's lines and assert 0% of its failure modes. The section-strip
desync (2026-08-18) had a dedicated passing test: it sampled the friendly
input (an adjacent tab jump) and asserted after `pumpAndSettle()` — which let
the stalled animation heal before the `expect` ran. Every rule below is a
scenario rule; none of them move the coverage number.

## Rule 1 — Assert the FIRST FRAME the user sees

After the state change under test, assert with `await tester.pump()` (one
frame), not `pumpAndSettle()`. Settling runs animations to completion and
un-mutes tickers — it *heals exactly the class of bug where the UI is wrong
until an animation lands*, which is what the user actually looks at.

- Use `.hitTestable()` on finders: a plain `find.byType` matches offstage and
  off-page-but-built widgets; hit-testable means "actually on stage".
- `pumpAndSettle()` belongs AFTER the assertions, to drain one-shot timers
  (theme status-reaction cues, snackbars) so the binding tears down clean.
- Exemplar: `test/features/tabs/presentation/widgets/`
  `request_section_offstage_sync_test.dart`.

## Rule 2 — Test the boundary classes of indexed UI, not one sample

For anything indexed (tab strips, `TabBarView`s, page views, reorderable
lists), one representative input is not coverage. The minimum set:

- a **non-adjacent** jump (SDK `TabBarView` warps adjacent and non-adjacent
  jumps through *different code paths* — non-adjacent temporarily swaps
  children in place);
- first ↔ last;
- a same-index no-op;
- for reorders: forward AND backward drags, and a drag whose indices cross a
  row the host doesn't know about (see the key-value editor's empty-key rows).

## Rule 3 — The offstage lifecycle gauntlet

Everything hosted inside `RequestView` lives in `TabContentStack`'s
keep-alive stack: up to `kMaxLiveTabViews` instances stay mounted inside
`Offstage(offstage: true)` + `TickerMode(enabled: false)`. Any widget whose
state can change while its request tab is inactive needs one test of shape:

1. mount on stage → 2. move offstage (`Offstage` + `TickerMode(false)`, same
wrappers as production) → 3. mutate the state it mirrors → 4. bring back on
stage → 5. **first-frame** assert (Rule 1).

Implementation corollary: **never call `.index =` / `animateTo()` /
`jumpToPage()` on a controller whose ticker may be muted.** A muted
`TabBarView` warp stalls mid-flight (non-adjacent: with children swapped) and
shows the wrong content when reactivated. The safe pattern is recreating the
controller at the new index (`request_config_section.dart`,
`unified_request_panel.dart`) — `TabBarView.didUpdateWidget` then jumps
synchronously with no animation machinery.

## Rule 4 — A test that locks in a limitation must cite why

A test titled "does not X" is a design decision wearing a test's clothes.
If the limitation is deliberate, the test body must point at the doc/issue
recording the decision; if there is no such record, treat the test as a
bug report, not a spec (`environment_resolver_test.dart` locked in
single-pass `{{var}}` resolution for months this way — no doc ever said
nested variables were unsupported, and the UI claimed they resolved).

## Rule 5 — `TextEditingController` listeners fire on selection-only changes

Clicking into a field or moving the caret notifies the controller with
UNCHANGED text. Any listener that does work on notification must guard with
a last-seen-text compare, or caret moves re-trigger it (two shipped bugs:
find-match reset to 1/N, tree-filter collapse overrides wiped).
`CodeFindPanel._onQueryChanged` is the reference implementation.

## Rule 6 — Bulk asserts need an adversarial pass, not more of themselves

Tests written alongside the implementation encode the author's model — the
bug lives outside that model by construction. For UI features, budget one
adversarial pass per feature that attacks lifecycle instead of confirming
intent: rapid switching, dispose-mid-async, state mutation while offstage,
resize, theme switch, ESC-dismissed dialogs. `integration_test/BACKLOG.md`
tracks the e2e side of this.

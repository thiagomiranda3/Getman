# QoL Wave 2 — daily-driver polish batch — design

**Date:** 2026-07-24
**Status:** Approved
**Feature:** 19 quality-of-life items across editing, safety, response reading,
navigation, and discoverability, shipped as one phased branch (`qol-wave-2`).

## Problem

A whole-app audit of the daily flows (request editing, response reading,
tree/tabs/history navigation, keyboard/chrome) surfaced recurring friction that
individually is small but collectively makes Getman feel less finished than it
is: deletes are irreversible-in-fact (confirm-only, no undo), a mis-closed tab
is gone, key-value rows can't be disabled or reordered, the find bar is
invisible and dead in half the response modes, headers aren't even selectable,
history is read-only, and almost nothing advertises its keyboard shortcut.

This spec covers the full audited batch minus one item the user deferred
(app-wide UI zoom).

## Decisions made during brainstorming

- **Instant delete + UNDO for single-item deletes** (one request node, one
  saved example, one history entry): no ConfirmDialog, a 5 s UNDO snackbar
  instead. Folders/collections/environments keep the ConfirmDialog **and**
  gain an UNDO snackbar after. CLAUDE.md's mandate is reworded from
  "irreversible actions confirm via ConfirmDialog" to "irreversible **or
  bulk** actions confirm via ConfirmDialog; single-item deletes use instant
  delete + UNDO snackbar".
- **Closed-tab stack is in-memory only** (depth 10, lost on quit). Session
  restore already preserves open tabs across restarts; the stack covers the
  "oops" moment only. No Hive changes.
- **UI zoom (E4) is deferred** — explicitly out of scope for this wave.
- **Delivery: one branch (`qol-wave-2`), phased waves, one PR** — items land
  as independent commits in dependency order.
- Grounded facts that shaped the design: query params are **derived from the
  URL** (never stored), so disabling a param requires parking it outside the
  URL; `showAppSnackBar` has **no action slot** today; `SettingsModel`'s next
  free Hive field is 30 (unused this wave); the next free Hive **typeId is
  13**; headers are a `Map<String, String>` (insertion-ordered).

## Item catalogue

| ID | Item | Size |
|----|------|------|
| A1 | Undo on deletes (snackbar action API + soft-delete) | M |
| A2 | Reopen closed tab ⌘⇧T | M |
| A3 | Save-all dirty tabs ⌘⌥S + close-all-saved | S |
| A4 | Revert unsaved changes on a dirty tab | S |
| B1 | Per-row enable/disable for params & headers | M |
| B2 | Drag-to-reorder + duplicate-row in KV editors | S/M |
| B3 | Auth secret masking with reveal toggles | S |
| B4 | URL autocomplete from history + collections | M |
| C1 | Find everywhere (visible button; works in all modes) | M |
| C2 | JSON tree filter + expand/collapse-all | S/M |
| C3 | Copyable headers/cookies | S |
| C4 | Word-wrap toggle + media action cluster | S |
| C5 | Copy as bug report | M |
| D1 | Desktop open-tabs list | S/M |
| D2 | Tree search by method + collapse-all | S |
| D3 | History management (delete/clear/day groups/empty state) | M |
| E1 | ⌘/ shortcuts cheat-sheet overlay | S |
| E2 | Shortcut hints in tooltips | S |
| E3 | Pre-send unresolved-{{var}} warning badge | M |

---

## A. Don't lose work

### A1 — Undo on deletes

**Snackbar API.** `showAppSnackBar` / `showAppSnackBarVia`
(`lib/core/ui/widgets/app_snack_bar.dart`) gain optional `actionLabel` +
`onAction`. The action renders as a themed `SnackBarAction`-equivalent inside
the existing chrome (same border/typography rules). Undoable snackbars use a
5 s duration; the default stays 2 s.

**Consumers and their capture semantics** (each captures a self-contained
snapshot; UNDO re-inserts it at the original position):

| Delete | Dialog? | Captured for undo |
|---|---|---|
| Single request node in tree | none (instant) | node + parent id + sibling index + linked saved examples |
| Folder / collection root | ConfirmDialog stays | full subtree + examples + collection variables + parent/index |
| Environment | ConfirmDialog stays | environment entity (incl. secret keys) |
| Saved example | none (instant) | example + owning node id + index |
| History entry (new, D3) | none (instant) | history record |
| History clear-all (new, D3) | ConfirmDialog stays | full history list |

Only the latest snackbar is undoable (a new delete replaces the previous
snackbar — standard messenger behavior; earlier deletes are accepted loss).
If UNDO fires after the restore target vanished (e.g. parent folder deleted
meanwhile), restore into the nearest surviving ancestor (or root), never
crash. Cookie-jar clearing keeps its current confirm-only flow (out of
scope). Tab closing is **not** undo — that is A2.

**CLAUDE.md** mandate reword per the brainstorming decision.

**Verify:** unit tests per consumer — delete → state without item; undo →
state deep-equals original (position included); folder undo restores subtree +
examples + variables; undo-after-parent-gone falls back to root.

### A2 — Reopen closed tab (⌘⇧T)

`TabsBloc` keeps an in-memory LIFO `_closedTabs` (max 10) of
`(tab entity snapshot incl. response & response history, panelId, strip
index)`. Pushed on every close path: single close, middle-click, close
others/left/right, close-all-saved (A3), and panel close (that panel's tabs in
visual order). Dirty tabs closed via DISCARD are pushed **with their dirty
content** — that is the point.

`ReopenClosedTab` event (⌘⇧T / Ctrl+Shift+T, registered in
`buildAppShortcuts`) pops the stack: restore into the original panel if it
still exists, else the active panel; clamp the index; make it the active tab.
Empty stack → brief snackbar "Nothing to reopen". Also a "REOPEN CLOSED TAB"
entry in the tab-chip context menu, disabled when the stack is empty. Not
persisted across restarts.

**Verify:** bloc tests — close/reopen round-trip (content + response +
panel + index), bulk-close push order, depth-10 eviction, dead-panel
fallback, dirty-content preservation.

### A3 — Save-all + close-all-saved

`SaveAllTabs` event (⌘⌥S): saves every dirty **collection-linked** tab across
all panels through the existing save path. Unlinked scratch tabs are skipped
and counted: snackbar "Saved 4 requests · 2 unlinked tabs skipped" (skip
clause omitted when zero; no-op → "Nothing to save").

"CLOSE SAVED TABS" joins the bulk-close group in the tab-chip context menu:
closes every non-dirty tab in the current panel (same scope as close-others),
never prompts, pushes each onto the A2 stack.

**Verify:** bloc tests — mixed dirty/linked matrix; snackbar counts; close-
all-saved leaves dirty tabs; closed tabs land on the reopen stack.

### A4 — Revert unsaved changes

Dirty **linked** tabs get a REVERT affordance: a small revert icon next to the
save button in the URL bar (visible only when dirty & linked) plus a "REVERT
CHANGES" tab-chip context-menu entry. ConfirmDialog ("Discard unsaved changes
to this request?") — this one is a bulk-ish destructive action on live edits,
so it keeps a dialog. Restores the linked node's saved config snapshot (the
same baseline `TabDirtyChecker` compares against). The current response and
time-travel timeline are untouched.

**Verify:** widget test — icon appears only dirty+linked; bloc test — revert
restores baseline, dirty flag clears, response preserved.

---

## B. Request editor ergonomics

### B1 — Per-row enable/disable for params & headers

**Entity** (`HttpRequestConfigEntity`): two new fields, both in `props`,
`copyWith`, and `withId`:

- `List<ParkedParamEntity> disabledParams` — a parked query param:
  `{String key, String value, int rowIndex}`. Unchecking a param removes the
  pair from the URL and parks it with its row position; re-checking removes it
  from the list and re-inserts into the URL at (clamped) `rowIndex`. Parked
  rows render greyed-out, interleaved at their remembered position.
- `Set<String> disabledHeaderKeys` — a disabled header **stays in the
  `headers` map** (preserving order) but is skipped at send and in code-gen.
  Editing a disabled row's key renames both the map key and the set entry.

**Hive:** `RequestConfigModel` gains `@HiveField(16) disabledParams`
(`List<ParkedParamModel>`, default `[]`) and `@HiveField(17)
disabledHeaderKeys` (`List<String>`, default `[]`). New `ParkedParamModel`
**typeId 13** (fields: key 0, value 1, rowIndex 2). Regen via build_runner;
update the typeId ledger in persistence-hive.md and CLAUDE.md's "next free"
to **14**.

**Send/code-gen:** `request_serializer.dart` skips disabled headers;
`code_gen_service.dart` mirrors the skip. Params need no send change (they are
already absent from the URL).

**UI:** `KeyValueListEditor` gains an optional leading checkbox column
(callback-driven so the env editor is unaffected). Disabled rows — parked
params and unchecked headers alike — render greyed-out in place. The params
tab composes enabled rows (URL-derived) + parked rows interleaved by
`rowIndex`; toggling updates URL + parked list atomically in one `UpdateTab`.

**Bulk edit:** `bulk_kv_codec.dart` adopts the Postman convention — a leading
`//` marks a disabled row, both directions.

**Interchange:** Postman import/export maps to its native `disabled` flags;
the git workspace mirror round-trips both new fields.

**Verify:** entity round-trip tests; serializer skip test; codec `//` tests;
Postman import/export round-trip; mirror round-trip; widget test for toggle →
URL rewrite + park/unpark position.

### B2 — Drag-to-reorder + duplicate-row

`KeyValueListEditor` renders a `ReorderableListView` with explicit drag
handles (`buildDefaultDragHandles: false` + `ReorderableDragStartListener` —
no long-press on desktop). The trailing auto-blank row is excluded from
reorder and has no duplicate/handle affordances.

Reorder semantics per host: params → reorder the derived list → URL query
rewrite; headers → rebuild the insertion-ordered map; env editor → persisted
map order.

Per-row duplicate action (icon next to delete): inserts directly below. For
map-backed hosts (headers, env) the copy's key gets a `-copy` suffix
(unique-key constraint); params duplicate exactly (duplicates are legal in a
query string).

**Verify:** widget tests per host — reorder updates URL/map order; duplicate
inserts below with correct key; blank row untouched.

### B3 — Auth secret masking

`auth_tab_view.dart`: Bearer TOKEN, Basic PASSWORD, and API KEY VALUE become
obscured fields with an eye reveal toggle (suffix icon), matching the env
editor's existing reveal pattern. Default hidden; toggle state is per-field,
session-only.

**Verify:** widget test — obscured by default, reveal toggles, value intact.

### B4 — URL autocomplete from history + collections

The URL bar's suggestion popup (currently `{{var}}`-only) gains a URL mode:
when the field has ≥3 typed chars and the caret is not inside `{{`, suggest
URLs merged from history (newest-first) and saved collection requests —
case-insensitive contains match, deduped, capped at 8. Selection replaces the
whole field text. Same keyboard handling as the variable popup (↑/↓/Enter/
Esc). Collection URLs are recomputed on collections-state change and cached;
history comes from the already-loaded bloc state.

**Verify:** unit test for the merge/rank/dedup/cap; widget test for trigger
conditions ({{ context keeps variable mode).

---

## C. Response readability

### C1 — Find everywhere

A visible find (magnifier) button joins the response toolbar; behavior per
mode:

- **PRETTY / RAW / opted-in large highlight:** invokes the existing
  `CodeFindPanel`.
- **HEADERS / COOKIES:** shows a filter field above the table (name+value
  contains).
- **TREE:** focuses the C2 filter box.
- **Large plain-text (preview and SHOW FULL):** a find field whose matches
  are computed **off the UI isolate** over the verbatim cache. While find is
  active the `SelectableText` is replaced by a windowed snippet view centered
  on the current match with highlight spans; n/N counter with next/prev
  re-centers the window. Windowed rendering keeps highlight cost independent
  of total body size, so no upper size cap is needed beyond the existing
  buffer limits. Closing find restores the normal view.

**Verify:** widget tests per mode; an isolate-search unit test with offsets;
a 1 MiB fixture exercising the windowed view.

### C2 — JSON tree filter + expand/collapse-all

TREE toolbar gains a filter field + expand-all/collapse-all buttons + match
count. Filter matches key names and primitive values (case-insensitive
contains); matches are shown with their ancestors auto-expanded. Guardrails:
auto-expansion caps at 500 revealed nodes ("Refine filter to see more");
expand-all on a tree over 2 000 nodes expands to depth 3 with a note instead
of freezing.

**Verify:** unit tests on the filter walk (matches, ancestor chain, caps);
widget test for expand/collapse-all.

### C3 — Copyable headers/cookies

The shared data-row slot (`app_components_defaults.dart` `_DefaultDataRow`,
plus any per-theme overrides of the same slot) renders name/value as
`SelectableText` and shows a hover copy icon per row (copies the value).
A COPY ALL button in the HEADERS/COOKIES toolbar copies `Key: value` lines.

**Verify:** widget test — selectability, per-row copy payload, copy-all
format; run against ≥2 themes to cover slot overrides.

### C4 — Word-wrap toggle + media action cluster

A word-wrap toggle icon in the response controls (text modes only; per-tab
session state; defaults preserve today's behavior: on for normal, off for
opted-in large). `ResponseMediaPanel` gains the standard action cluster —
SAVE TO FILE (surfaced at panel level, not just the RAW card), SAVE AS
EXAMPLE, COMPARE — with COPY enabled only for text-ish media (csv/html).

**Verify:** widget tests — wrap toggle flips editor option; media panel
exposes cluster; copy disabled for binary/image.

### C5 — Copy as bug report

A "COPY AS BUG REPORT" action beside the existing copy button composes a
markdown bundle to the clipboard:

```
### <METHOD> <resolved URL>
<curl block — code_gen_service curl generator, active-env resolved,
 secret env values masked as •••>
**Response:** <status> · <durationMs> ms · <size>
<headers block>
<body block — truncated at 50 KB with "(truncated: full size N)" note>
```

Resolution uses the active environment chain at compose time; any value whose
source key is in `secretKeys` is masked. Snackbar confirms the copy.

**Verify:** unit test on the composer — masking, truncation, empty-body case.

---

## D. Navigation & wayfinding

### D1 — Desktop open-tabs list

A list icon button at the right end of the desktop/tablet tab strip opens an
anchored, searchable dropdown of **all open tabs grouped by panel** (method
badge + name + dirty star), reusing the phone switcher sheet's data assembly.
Click activates panel + tab; Esc closes. Compact/phone keeps the existing
sheet.

**Verify:** widget test — grouping, search filter, activation dispatches
panel+tab events.

### D2 — Tree search by method + collapse-all

`_filterNodes` also matches `node.config?.method` (case-insensitive), so
"post" finds POST requests — consistent with the palette. A collapse-all icon
button sits beside the tree search field and clears the expansion map.

**Verify:** unit test for method matching; widget test for collapse-all.

### D3 — History management

`HistoryBloc` gains `DeleteHistoryEntry(id)` and `ClearHistory` events backed
by new repository methods. UI: hover ✕ per row (instant + undo per A1);
CLEAR ALL toolbar button (ConfirmDialog + undo). Rows group under day headers
(TODAY / YESTERDAY / weekday-month-day). The zero-history empty state becomes
first-run guidance ("No requests sent yet — sent requests appear here
automatically") — distinct from the search-miss "NO RESULTS FOUND".

**Verify:** bloc tests for delete/clear/undo; grouping unit test around
midnight boundaries; empty-state widget test (fresh vs filtered).

---

## E. Keyboard & discoverability

### E1 — ⌘/ shortcuts cheat-sheet overlay

⌘/ (Ctrl+/ elsewhere) opens a dialog reusing the Settings → SHORTCUTS tab
content — the table widget is extracted so there is a single source. Esc or
⌘/ closes. The new shortcut is itself listed. If re_editor swallows ⌘/ while
a code editor has focus, strip it in `AppCodeShortcutsActivatorsBuilder` the
same way ⌘S is handled.

### E2 — Shortcut hints in tooltips

Shortcut labels come from one platform-aware source (the same table the
settings tab and E1 overlay read), rendered as "Action — ⌘X". Applied to:
SEND (which gains its first tooltip, "Send — ⌘↩"), save ("Update Request —
⌘S"), beautify ("Beautify JSON — ⌘B"), env selector ("Environment · name —
⌘E"), new tab, new panel, focus-URL, command-palette entry points.

**Verify (E1+E2):** widget test — overlay opens/closes via shortcut; tooltip
strings include platform-correct hints; single-source table drives both.

### E3 — Pre-send unresolved-{{var}} warning

A warning chip appears left of SEND when the request references `{{vars}}`
that resolve to nothing in the active chain (URL, headers, params, text
bodies, graphql variables, auth values). Count on the chip; click opens a
popover listing the unresolved names with an "Open environment editor"
action. Never blocks sending. Computation reuses the existing resolver,
memoized per (config revision, active env revision) and debounced off the
critical path.

**Verify:** unit tests on the collector (all field sources, dedup); widget
test — chip hidden when clean, popover lists names.

---

## Cross-cutting

- **Hive:** new typeId 13 (`ParkedParamModel`), config model fields 16/17.
  Regen, ledger update in persistence-hive.md, CLAUDE.md next-free → 14.
- **CLAUDE.md:** mandate reword (A1); Hive next-free bump.
- **Wiki (same work, per mandate):** pages touched — request editor
  (B1/B2/B3/B4), responses (C1–C5), collections tree (D2, A1), history (D3),
  tabs & panels (A2/A3/A4, D1), keyboard shortcuts (⌘⇧T, ⌘⌥S, ⌘/, tooltip
  hints), settings (shortcuts tab note). Verbatim UI labels.
- **Testing bar:** every item lands with tests (TDD); all four static passes
  + format + full `fvm flutter test` green between waves.

## Delivery — waves on `qol-wave-2`

1. **Foundations:** snackbar action API; Hive fields + `ParkedParamModel` +
   regen; entity `copyWith`/`props`/`withId`; single-source shortcut-label
   table (feeds E1/E2).
2. **Editor:** B1, B2, B3, B4 (+ bulk codec `//`).
3. **Safety:** A1 consumers, A2, A3, A4.
4. **Response:** C1, C2, C3, C4, C5.
5. **Navigation:** D1, D2, D3 (D3 depends on A1).
6. **Discoverability:** E1, E2, E3.
7. **Sweep:** wiki sync, persistence ledger, CLAUDE.md, final gates.

## Out of scope

- **E4 UI zoom / text scale** — user-deferred; `SettingsModel` field 30
  remains free.
- Cookie-jar clear-all undo.
- Command-palette action system (backlog DL4), timing waterfall (DL3) — both
  remain separate backlog items.

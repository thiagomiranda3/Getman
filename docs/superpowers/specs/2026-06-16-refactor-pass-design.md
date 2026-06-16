# Refactoring Pass — God-file Splits + Verified Dedup (2026-06-16)

## Goal

Reduce structural debt in the largest / most-tangled files and remove confirmed
code duplication, **without changing any user-facing behavior**. This is a
maintenance pass: moves and extractions, not redesigns.

Scope was chosen as **HIGH + MEDIUM god-file splits + verified dedup**. The
performance front was investigated and found **already clean** (see
"Performance: no-op" below) — it is intentionally excluded.

## Non-goals

- No new features, no UX changes, no theme changes.
- No Hive `@HiveType`/`@HiveField` changes (no migrations).
- No BLoC→BLoC coupling, no `sl<T>()` in widgets, no hardcoded sizes/colors —
  all CLAUDE.md §4.8/§6 mandates hold.
- No wiki edit (nothing about how a feature is *used* changes).

## Working agreement (per `docs/BACKLOG.md`)

1. **One concern per commit**, message `type(scope): summary`, ending with
   `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
2. **Green between every commit**: `fvm flutter analyze` (0 issues),
   `fvm dart run custom_lint` (0), `fvm dart run bloc_tools:bloc lint lib` (0),
   `fvm dart format` clean, and `fvm flutter test` 100%.
3. **Verify compile, not just analyze** — `analyze` has given false passes on
   generic-variance issues; `fvm flutter test` (CFE) is the real gate.
4. Extractions are **behavior-preserving**: the moved code is identical; only
   its file/visibility changes. Add tests only where a split creates a newly
   testable unit.
5. Execute on branch `dev`.

---

## Part A — God-file splits

All splits keep feature-specific widgets inside that feature's
`presentation/widgets/`; only genuinely reusable atoms move to
`lib/core/ui/widgets/`. Private (`_Foo`) widgets that move to their own file
become public (`Foo`) only when they must be imported; otherwise they stay
private within a co-located file.

### A1. `tabs_bloc.dart` (518) → extract `RequestManager` *(do first; cheap)*

- **Today:** a private `_RequestManager` (≈ lines 25–55) maps
  `tabId → NetworkCancelHandle` with `cancel`/`finish`/`cancelAll`. Backlog-flagged.
- **Move:** new `lib/features/tabs/presentation/bloc/request_manager.dart`
  containing a public `RequestManager` class. `TabsBloc` instantiates it as
  before; behavior identical.
- **Why:** isolates in-flight cancellation state; makes it unit-testable
  independent of the bloc.
- **Risk:** LOW. It only touches the cancel-handle map; no event flow changes.
- **Verify:** existing `tabs_bloc` tests stay green; add a small
  `request_manager_test.dart` (register → cancel → finish → cancelAll).

### A2. `collections_list.dart` (1036) → split into 5 files *(biggest payoff)*

Current private classes:
- `_CollectionNodeWidget` + state (≈ 413–648) — folder/request row, hover, drag.
- `_NodeContextMenu` (≈ 650–832) — rename/delete/favorite/export menu + dialogs.
- `_ExampleRow` + state (≈ 853–946) — saved-example row, opens unlinked tab.
- `_ExampleMenu` (≈ 950–1036) — rename/delete example.

- **Extract (feature-local, under `collections/presentation/widgets/`):**
  - `collection_node_row.dart` ← `_CollectionNodeWidget` (+ state).
  - `collection_node_menu.dart` ← `_NodeContextMenu`.
  - `example_row.dart` ← `_ExampleRow` (+ state).
  - `example_menu.dart` ← `_ExampleMenu`.
  - `collections_list.dart` keeps the `CollectionsList` widget + state: search
    debounce, `_expandedIds` (Set) expansion ownership, tree rebuild,
    import coordination, root-level `DragTarget`, empty state.
- **Hard constraints (must not regress):**
  - **H2:** id-keyed expansion via `_expandedIds` Set reseeded into
    `TreeViewNode(expanded:)` each rebuild — stays entirely in `collections_list.dart`.
  - Drag-and-drop (`Draggable<String>`/`DragTarget<String>` carrying `node.id`).
  - `ValueKey(node.id)` on tree tiles; fixed `AppLayout.treeRowExtent`.
  - The `_TreeItem` node-vs-example union semantics.
- **Approach:** extract in ≥4 small commits (one widget cluster per commit) so
  each diff is reviewable and the suite re-verifies between moves. Callbacks
  (onRename, onDelete, onOpenExample, …) are passed in from `collections_list`
  so the extracted widgets stay dumb and bloc-agnostic.
- **Risk:** MEDIUM — many cross-references and threaded state. Mitigated by
  small commits + existing collections widget tests + a real compile each step.

### A3. `response_body_view.dart` (603) → extract viewer + controls

- **Today:** mixes large-vs-small body rendering, a pretty/raw sync pipeline,
  the copy/save/compare/save-as-example button cluster, and `_PrettyRawToggle`.
- **Extract (under `tabs/presentation/widgets/response/`):**
  - `response_body_controls.dart` ← the copy / save-to-file / compare /
    save-as-example button builders (keep their existing `buildWhen` gates;
    target-lookup helpers `_exampleTargets`/`_historyTargets` move with them).
  - `response_large_body_view.dart` ← the large-mode banner + plain/editor
    fallback path.
  - `response_body_view.dart` keeps the main widget, the `_syncBody` pretty/raw
    pipeline (mount guards, pending-id, auto-prettify setting), and
    `_PrettyRawToggle` (small, used only here).
- **Risk:** MEDIUM — the sync pipeline is intricate; keep it in place untouched.
  Extract only the leaf UI. Preserve the `kLargeResponseViewerChars` /
  `kResponseBodyTooLargePlaceholder` behavior and the `// ignore:
  avoid_hardcoded_brand_colors` dynamic-contrast line.
- **Verify:** existing response widget tests; manual: large body, pretty/raw
  toggle, compare picker, save-as-example.

### A4. `rules_tab_view.dart` (540) → extract rows + card

- **Today:** `_ExtractionRuleRow` (+state), `_AssertionRow` (+state), shared
  `_RuleCard`, plus `_Header`/`_AddButton`.
- **Extract (under `chaining/presentation/widgets/`):**
  - `extraction_rule_row.dart` ← `_ExtractionRuleRow` (+ state).
  - `assertion_rule_row.dart` ← `_AssertionRow` (+ state).
  - `rule_card.dart` ← `_RuleCard` (reusable card chrome; stays in the feature
    unless a second consumer appears — do **not** speculatively move to core).
  - `rules_tab_view.dart` keeps the list + load state + headers/add buttons.
- **Risk:** LOW–MEDIUM. Each row owns its controllers + emit pipeline; moving
  the class wholesale preserves that. Keep the controller-lifetime logic intact.

### A5. `spec_import_dialog.dart` (572) → split source + preview

- **Today:** source picker (FILE/PASTE/URL via `_SourceSelector`/`_SourceButton`),
  parse-error display, and the selectable preview tree (`_ImportPreview`,
  `_FolderRow`, `_LeafRow`, `_ErrorText`).
- **Extract (under `collections/presentation/widgets/`):**
  - `spec_import_source.dart` ← `_SourceSelector`, `_SourceButton`, source input.
  - `spec_import_preview.dart` ← `_ImportPreview`, `_FolderRow`, `_LeafRow`,
    `_ErrorText`.
  - `spec_import_dialog.dart` keeps the `SpecImportDialog` state machine
    (source → parse → preview → dispatch). Stays bloc-agnostic (design lock).
- **Risk:** LOW–MEDIUM. The selection tri-state is threaded via callbacks.

---

## Part B — Verified dedup

### B1. `_firstSchemeName` verbatim dupe *(HIGH confidence, trivial)*

- **Today:** identical function in `openapi_v3_normalizer.dart:270–276` and
  `swagger_v2_normalizer.dart:216–222`.
- **Fix:** move to a shared helper in `lib/core/utils/openapi/` (e.g.
  `spec_helpers.dart`, top-level `firstSecuritySchemeName(Object?)`); both
  normalizers import it. Delete the two private copies.
- **Risk:** NONE (pure function, no behavior change).
- **Verify:** existing openapi/swagger normalizer tests stay green.

### B2. `BodyTypeUtils.applyContentType` *(MEDIUM — behavioral nuance)*

- **Today:** Content-Type-by-body-type logic duplicated:
  - `request_serializer.dart:68–119` (`buildBody`, interleaved with payload).
  - `code_gen_service.dart:72–92` (`_effective`).
- **⚠️ Behavioral difference:** for `binary`, the serializer sets
  `application/octet-stream` **only when a file path exists** (it returns early
  with `null` + no header when `bodyFilePath` is empty); code-gen sets it
  **unconditionally**. A naive shared helper that always sets it would change
  the serializer's no-file behavior.
- **Fix:** extract `BodyTypeUtils` in `lib/core/utils/`:
  - `applyContentType(Map<String,String> headers, BodyType type)` applies the
    urlencoded/multipart/binary header rules (binary = set octet-stream unless a
    custom type is present).
  - Code-gen `_effective` calls it directly.
  - `request_serializer.buildBody` keeps its `binary`-path guard: it calls the
    helper **only inside the branch where it already sets the header** (i.e.
    after confirming a non-empty path), so the no-file case stays header-free.
- **Risk:** MEDIUM. Mitigated by a **regression test first** (TDD): assert that
  `buildBody` with `bodyType: binary` and empty/`null` `bodyFilePath` leaves
  Content-Type unset and returns null — written and passing *before* the extract.
- **Verify:** new `body_type_utils_test.dart` (each body type → expected header
  mutation) + the binary-no-file serializer test + existing serializer/code-gen tests.

### B3. code-gen internal cleanup *(LOW–MEDIUM, pure-internal)*

- **Header iteration:** the one-liner
  `headers.forEach((k, v) => buf.write("$indent'$k': '${_sq(v)}',\n"))` repeats
  in `_fetch` (≈141), `_python` (≈186), `_nodeAxios` (≈238) → extract a private
  `_writeHeaders(StringBuffer, Map, String indent)`.
- **Escapers:** `_sq` (≈477) and `_dq` (≈505) are the same logic with a
  different quote char → unify into one private `_escape(String, String quote)`,
  keep `_sq`/`_dq` as thin wrappers (call sites unchanged).
- **Risk:** LOW. All private to `code_gen_service.dart`; output must be
  byte-identical.
- **Verify:** existing `code_gen_service` tests must produce identical strings.

---

## Performance: no-op (investigated, already clean)

Every candidate surfaced was verified against the live code and found already
handled — recorded here so it is not re-investigated:

- `response_headers_view.dart:43` / `response_cookies_view.dart:39` — the
  `toList()` / cookie parse run inside a `buildWhen` gated by
  `identical(prev.response, next.response)`, so they fire only when a new
  response arrives, not per-frame. (A proposed `elementAt` "fix" would make it
  O(n²) — explicitly rejected.)
- `RequestKindMethodSelector` — the URL bar's `BlocConsumer.buildWhen`
  (`url_bar.dart:151–159`) excludes `config.url`; URL text is pushed via the
  `listener` + `_setControllerPreservingEnd`. So the method dropdown does **not**
  rebuild per keystroke; building 7 items on a rare method/kind change is fine.
- `form_data_editor.dart` — rows already keyed by a stable `row.id`
  (`ValueKey('name_${row.id}')`/`val_…`), preserving controllers/focus.
- Confirmed-good elsewhere: JSON prettify via `compute()`, painter point/Paint
  caching, debounced tab persistence, narrow `buildWhen`/`listenWhen` on hot
  paths, proper disposal of timers/subscriptions, debounced tree filtering.

**Decision:** no perf commits. Manufacturing changes here would add risk for no
measurable gain.

---

## Suggested execution order

1. B1 (`_firstSchemeName`) — trivial warm-up, banks a green.
2. A1 (`RequestManager`) — cheap, backlog-flagged, adds a test.
3. B3 (code-gen internal cleanup) — small, self-contained.
4. B2 (`BodyTypeUtils`) — test-first, then extract.
5. A4 (`rules_tab_view`) — clean row/card extraction.
6. A5 (`spec_import_dialog`) — source/preview split.
7. A3 (`response_body_view`) — controls + large-body viewer.
8. A2 (`collections_list`) — last + largest; ≥4 sub-commits.

Rationale: cheap/safe items first to bank momentum and keep the suite green,
the riskiest/largest split (A2) last when the surrounding code is freshest in
context.

## Done-bar

- Each item: full static-analysis stack clean (analyze + custom_lint +
  bloc_lint) + `dart format` clean + `fvm flutter test` 100% green, verified by
  a real CFE compile.
- No file in the touched set retains a god-file responsibility; new files each
  have one clear purpose.
- No behavior change observable to a user; no wiki edit required.

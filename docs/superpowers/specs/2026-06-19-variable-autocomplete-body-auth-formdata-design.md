# Variable autocomplete + highlight + hover for body, auth & form-data

**Date:** 2026-06-19
**Status:** Approved design, pending implementation plan
**Extends:** `2026-06-17-variable-autocomplete-design.md` (original URL/params/headers work)

## Goal

Bring the full URL-bar variable experience to every place a user can type a
`{{var}}`:

- **`{{`-triggered autocomplete dropdown**
- **`{{var}}` color highlighting** (resolved vs. unresolved)
- **hover preview popover** (variable value / source / secret masking)

Target fields that currently lack it:

1. **Auth** — bearer token, basic auth username/password, API-key name/value
2. **Form-data values** — multipart & urlencoded value fields
3. **Raw / JSON body** — the `re_editor` code editor

Variable source set, applied **everywhere** (including aligning the existing
params/headers fields): **active environment vars → inherited collection
folder vars → dynamic built-ins** (`$guid`, `$timestamp`, …), matching what the
URL bar already does.

## Non-goals

- Highlighting/autocomplete on **keys** (param/header/form-data names, auth
  field labels) — only values, matching current behavior and send-time
  resolution scope.
- Resolving variables anywhere new at send time — resolution plumbing is
  unchanged; this is purely an editing-UX feature.

## Existing building blocks (reused, not rebuilt)

| Piece | Location | Role |
|---|---|---|
| `VariableAutocomplete` | `lib/core/ui/widgets/variable_autocomplete.dart` | Overlay + `{{` trigger over a `TextEditingController` |
| `VariableHighlightController` | `lib/core/ui/widgets/variable_highlight_controller.dart` | `TextEditingController` subclass: colors `{{var}}`, fires `onVariableEnter/Exit` |
| `VariableHoverController` / `VariableHoverContext` | `lib/core/ui/widgets/variable_hover_popover.dart` | Hover popover overlay + its data |
| `buildVariableSuggestions` | `lib/core/utils/variable_suggestions.dart` | Filter + rank suggestions |
| `detectActiveVariableQuery` | `lib/core/utils/variable_autocomplete_query.dart` | `{{`-query detection at a caret offset |
| `VariableResolutionHelper.classify(Layered)` | `lib/core/utils/variable_resolution_helper.dart` | Resolve a name → value/kind/source |
| layered context logic | `_layeredContext` in `url_bar.dart` | env + collection vars for a tab |

## Architecture

### Component 1 — `VariableTextField` atom

**New:** `lib/core/ui/widgets/variable_text_field.dart`.

Bundles the wiring currently inlined inside `KeyValueListEditor` (lines ~181–206
+ 352–360) into one reusable widget:

- owns a `VariableHighlightController` (seeded from `initialValue`/an external
  controller),
- pushes theme colors (`appPalette.variableResolved/Unresolved`) and the active
  variable map in `didChangeDependencies` (diffed — only notifies on real
  change, per the existing controller contract),
- wires `onVariableEnter/Exit` to a `VariableHoverController`,
- wraps its `TextField` in `VariableAutocomplete` with a `suggestionsFor`
  closure built from the context's variables.

**Props:** `VariableHoverContext context`, `TextEditingController controller`
(caller-owned, so existing echo-suppression keeps working), `FocusNode?`,
`ValueChanged<String> onChanged`, `bool obscure`, `String? hintText`, key knobs.
When `context.variables` is empty it degrades to a plain styled field (no
overlay, no highlight) — same as a null context today.

**Adoption:** auth fields and form-data value fields use it directly.
`KeyValueListEditor`'s value field is refactored to use it too, deleting the
duplicated inline wiring (one behavior, one place). Param/header **name** fields
and form-data file rows are untouched.

> Note: `VariableTextField` must accept a **caller-owned controller** (not just
> an initial string) because auth/form-data/kv all rely on holding their own
> controllers for echo-suppression across the bloc round-trip. The atom adds
> highlight/hover/autocomplete *around* that controller; it does not own value
> lifecycle. The controller it's handed must be a `VariableHighlightController`
> (the atom upgrades/asserts this) so `buildTextSpan` highlighting works.

### Component 2 — shared tab-scoped layered context

**Promote** the env-only `_VariableContextBuilder`
(`request_editor_tabs.dart:40`) into a shared, **layered**
`TabVariableContextBuilder` (new file in `lib/core/ui/widgets/` or a
tabs-presentation shared file).

It computes the same context the URL bar's `_layeredContext` does — active
environment vars merged over the tab's inherited collection folder vars (env
wins), plus the env name + merged secret keys — and rebuilds on env-set /
active-env-id / collection-tree changes. It needs the tab's linked collection
node id, so it takes the `tabId` (or reads `TabsBloc` for it) like the URL bar.

`VariableHoverContext` gains nothing new structurally (it already carries
`variables` + `secretKeys` + `environmentName`); the change is **what fills it**
(layered, not env-only). All five consumers — params, headers, auth, form-data,
body — read from this one builder, so suggestions are identical everywhere.

> This intentionally changes params/headers behavior: they currently suggest
> env-only and will now also suggest collection vars + dynamics. That is the
> "align params/headers" decision, approved.

### Component 3 — Auth integration

`auth_tab_view.dart`: wrap the field column in `TabVariableContextBuilder` and
replace `_field(...)`'s inner `TextField` with `VariableTextField` (passing the
context, the existing per-field controller, the `obscure` flag for
password/api-key value). Echo-suppression (`_lastEmitted`, `_setIfChanged`) is
unchanged. `inherit`/`none` auth types render no fields → no context needed.

### Component 4 — Form-data integration

`form_data_editor.dart`: wrap in `TabVariableContextBuilder`; the value
`TextField` (line ~175, non-file rows only) becomes a `VariableTextField` using
the row's `valueController`. File rows and the name field are unchanged. `_emit`
flow unchanged.

### Component 5 — Body autocomplete (`CodeAutocomplete`)

`re_editor 0.9.0` ships `CodeAutocomplete` (verified against the installed lib
source). Wrap the body `CodeEditor` (in `json_code_editor.dart` /
`request_view.dart`'s `_RawBodyEditor`) with it.

- **`VariablePromptsBuilder implements CodeAutocompletePromptsBuilder`** (new):
  `build(context, codeLine, selection)` runs our existing
  `detectActiveVariableQuery(codeLine.text, selection.extentOffset)`. On a hit
  it returns a `CodeAutocompleteEditingValue` with `input = query` and
  `prompts` built from `buildVariableSuggestions(...)`. Each suggestion becomes
  a small `CodePrompt` subclass whose `.autocomplete` yields a
  `CodeAutocompleteResult` of `word = name` (+ `}}` when
  `!hasClosingBraces`) and a collapsed selection at `word.length`.
  - re_editor's apply path deletes `[caret - input.length, caret]` and inserts
    `word`, leaving the `{{` intact and placing the caret after the inserted
    text — replicating `VariableAutocomplete._acceptAt`'s `}}` logic.
  - `build` is invoked on every line-changing keystroke (verified:
    `_updateAutoCompleteState` → `show` in `_code_editable.dart`), so the menu
    appears right after `{{`, exactly like the URL bar.
- **`viewBuilder`** (new `PreferredSizeWidget`): renders the same
  name + source-badge + resolved-preview rows as `VariableAutocomplete._row`,
  themed via `context.app*`. Keyboard nav (↑/↓ + Enter) is handled by the
  package's actions; **Tab-to-accept is not wired by re_editor** (minor
  divergence from the `TextField` overlay — acceptable, noted).

Feed the body controller the active variable map (needed by Component 6) — the
controller stays the same `CodeLineEditingController` from
`createJsonCodeController()`, just configured with a variable-aware span builder.

### Component 6 — Body highlighting (flat-run merge)

Extend the body's span building so `{{var}}` tokens are colored on top of JSON
highlighting:

- Produce JSON token runs for the line (today: `jsonHighlightSpanBuilder` via
  `re_highlight`'s `TextSpanRenderer`).
- Find `{{var}}` ranges in the line (`EnvironmentResolver.findVariables` /
  `detectActiveVariableQuery`'s pattern) and **override** the color of those
  character ranges with `variableResolved` / `variableUnresolved` (decided by
  classifying the name against the active variable map). Variable color wins
  inside `{{…}}`.
- Implementation approach: render JSON into a **flat run list** `(start, end,
  style)` instead of (or in addition to) the nested `TextSpan`, overlay the
  variable ranges, then emit a flat `TextSpan` with children. This avoids
  surgery on a nested span tree. Lines that don't parse as JSON still get
  variable coloring over the base style.
- The active variable map reaches this builder via the tab context (the
  span builder is rebuilt / closes over the current map; on env change the
  editor re-highlights visible lines).

`createJsonCodeController()` gains an optional variables source (or a setter the
body widget updates on context change). **Do not reinstate `codeTheme`** — the
gotcha in CLAUDE.md still holds; coloring stays in the span builder.

### Component 7 — Body hover ⚠️ (highest risk) — DEFERRED (spike result, 2026-06-20)

> **RESOLUTION:** The Task 9 spike confirmed body hover is **not feasible in
> `re_editor 0.9.0` without forking the package**, so it is **deferred** per the
> fallback below. Evidence: the editor's render object is `_CodeFieldRender`
> (private), reached via a private `editorKey`; the position-from-offset method
> (`CodeLineRenderParagraph.getPosition(Offset)`) lives on private
> line/paragraph internals; the public `CodeLineEditingController` exposes no
> position↔offset API and `CodeEditor` exposes no hover/position callback. The
> `TextSpan.onEnter/onExit` route also fails because re_editor paints with a
> custom render object (not `RenderParagraph`), so span hover callbacks never
> fire. **Delivered:** body autocomplete + highlighting. **Not delivered:**
> body hover (URL, params, headers, auth, form-data retain full hover). Revisit
> if/when re_editor exposes a public position API or a fork is justified.

`re_editor` paints lines through a custom render object, so Flutter's
`TextSpan.onEnter/onExit` hover callbacks are not expected to fire (unlike the
`RenderParagraph`-backed `TextField`). Plan:

- Wrap the editor in a `MouseRegion`. On hover, map the pointer's global
  position → a text offset using the editor's render object / public position
  API, test whether that offset falls inside a `{{var}}` token on that line,
  and drive the existing `VariableHoverController` to show the popover anchored
  at the pointer.

**Risk & fallback:** this depends on `re_editor` exposing a usable
position↔offset mapping without forking internals (`_CodeFieldRender` has
`calculateTextPositionScreenOffset` for offset→screen; the inverse used by
selection/tap may not be public). The implementation plan will spike this
first. **If it requires forking re_editor**, the fallback is to ship body
**autocomplete + highlight** now and track body **hover** as a follow-up —
auth, form-data, params, headers, and URL all retain full hover regardless.
This is the one place the delivered scope may narrow; it will be surfaced
during the plan's spike, not silently dropped.

## Data flow

```
EnvironmentsBloc + SettingsBloc + CollectionsBloc/TabsBloc
        │  (active env id, env vars, collection tree, linked node id)
        ▼
TabVariableContextBuilder  ──►  VariableHoverContext { variables, secretKeys, environmentName }
        │
        ├─► VariableTextField (auth fields, form-data values, kv values)
        │        └─ VariableHighlightController + VariableAutocomplete + VariableHoverController
        │
        └─► Body editor
                 ├─ VariablePromptsBuilder + viewBuilder  (autocomplete)
                 ├─ variable-aware span builder           (highlight)
                 └─ MouseRegion + VariableHoverController  (hover, risk-gated)
```

No new blocs, events, or persisted state. No domain/data changes. Pure
presentation-layer wiring over existing utilities.

## Testing

Widget tests, mirroring existing URL-bar/params autocomplete tests:

- **`VariableTextField`** (atom): `{{` opens menu; typing filters; Enter/Tap
  inserts `{{name}}` and positions the caret; existing-`}}` case inserts just
  the name; highlight colors resolved vs. unresolved; hover shows the popover
  (incl. secret masking); empty context → plain field, no overlay.
- **Auth**: each field type (token / user / pass / api-key name / value)
  autocompletes; password stays obscured while autocompleting.
- **Form-data**: value field autocompletes; file rows / name field do not.
- **Body**: `{{` opens the `CodeAutocomplete` menu; accept inserts `{{name}}`
  with correct caret; non-`{{` typing shows nothing; highlight colors a
  `{{var}}` inside a JSON string; (hover test gated on Component 6/7 outcome).
- **Context**: params/headers/auth/form-data/body all surface env + collection
  + dynamic names from one `TabVariableContextBuilder`.

Full done-bar before claiming complete: `fvm flutter analyze`,
`fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`,
`fvm dart format` clean, `fvm flutter test` green.

## Wiki sync

Update the variables page (`Getman.wiki.git`) to state that `{{var}}`
autocomplete, highlighting, and hover preview now apply to **request body
(raw/JSON), auth fields, and form-data values** — not just URL/params/headers —
and that suggestions include collection-scoped and dynamic variables in every
field. (Body hover wording conditional on Component 7 outcome.)

## Risks summary

1. **Body hover (Component 7)** — may require re_editor internals; fallback is
   defer hover-on-body only. *Spike first in the plan.*
2. **Body highlight merge (Component 6)** — flat-run merge must not regress
   existing JSON coloring; covered by a "JSON line with no vars renders
   identically" test.
3. **params/headers behavior change** — they gain collection + dynamic
   suggestions; intended, but call it out in the PR/wiki.

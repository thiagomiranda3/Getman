# `{{variable}}` Autocomplete — Design

**Date:** 2026-06-17
**Branch:** `feat/variable-autocomplete`
**Status:** Approved (design); ready for implementation plan.

## Summary

Add an in-field autocomplete menu for `{{variable}}` references. Typing `{{`
(or pressing Cmd/Ctrl+Space) opens a keyboard-navigable menu of known variable
names — active-environment variables, inherited collection/folder variables,
and dynamic built-ins (`$guid`, `$timestamp`, …) — that filters as the user
types and inserts the chosen `name}}` on accept. This closes the gap with
Postman's variable suggestions, building on Getman's existing variable
highlighting / hover-resolution infrastructure rather than a parallel system.

## Scope

**In scope (this PR):** the inputs already backed by `VariableHighlightController`
(a `TextEditingController` subclass):
- the URL bar (`url_bar.dart`)
- params + headers **value** fields (`KeyValueListEditor`)

**Out of scope (explicit, possible follow-ups):**
- the request body editor — it is `re_editor`'s `CodeLineEditingController`, a
  different integration surface.
- the AUTH tab fields — plain controllers, would need separate wiring.
- the environment/collection variable **editors** — they intentionally pass no
  `variableContext` to `KeyValueListEditor`, so they remain unchanged.

## Decisions (confirmed with user)

1. **Fields:** URL + params + headers (the `VariableHighlightController` seam).
2. **Trigger:** typing `{{` opens + live-filters the menu; **and** Cmd/Ctrl+Space
   opens it on demand. Enter / Tab / click accept; Esc dismisses.
3. **List contents:** active-environment vars + inherited collection vars +
   dynamic vars, each with a source tag and value preview; secrets masked.
   Reuses `VariableResolutionHelper` so previews match the hover popover.

## Approach: keyboard interception

The hard part is making ↑/↓/Enter/Tab/Esc drive the menu **only while it is
open**, without breaking normal typing or caret movement when it is closed.

- **Chosen — `Shortcuts` + `Actions` wrapping the field, gated by menu-open.**
  Wrap the `TextField` in a `Shortcuts` map (arrowUp/arrowDown/enter/tab/escape
  + Cmd/Ctrl+Space) → `Actions` whose `Action.isEnabled` returns `false` while
  the menu is closed. A wrapping `Shortcuts` is encountered *before*
  `DefaultTextEditingShortcuts` during key-event resolution (resolution walks
  from the focused node upward, nearest first), so it wins for those keys when
  enabled and falls through to normal editing when disabled. This cleanly
  resolves Tab-vs-focus-traversal and Enter-vs-onSubmitted. Cmd/Ctrl+Space's
  Action is always enabled.
- **Rejected — `RawAutocomplete`.** Its `optionsBuilder(text)` model treats the
  whole field as the query; our trigger is a mid-string `{{` token with custom
  `name}}` insertion. Adapting it is more code than the chosen approach.
- **Rejected — raw `Focus.onKeyEvent` on an ancestor.** Event ordering versus
  `EditableText` for single-line arrows/Enter is unreliable.

## Modules — new

### 1. `lib/core/utils/variable_autocomplete_query.dart` (pure Dart)

The trigger + insertion brain. No Flutter imports.

```dart
class ActiveVariableQuery {
  final int replaceStart;   // index where the name starts (just after `{{`)
  final int replaceEnd;     // caret offset (end of the typed query)
  final String query;       // text between `{{` and the caret (may be empty)
  final bool hasClosingBraces; // `}}` immediately follows the token
}

ActiveVariableQuery? detectActiveVariableQuery(String text, int caretOffset);
```

Logic: scan backward from `caretOffset` for the nearest `{{` with no intervening
`}}` or `{{`. The query is `text[afterBraces .. caret]`. If any character in
that span is not a legal identifier char (`\$?[A-Za-z0-9_\-.]`), there is no
active query (returns null) — e.g. a space or `/` ends the token. Detect whether
`}}` immediately follows the caret to avoid doubling braces on insert. Returns
null when the selection is non-collapsed.

### 2. `lib/core/utils/variable_suggestions.dart` (pure Dart)

```dart
class VariableSuggestion {
  final String name;                  // "baseUrl" or "$guid"
  final ResolvedVariable classification; // reused from VariableResolutionHelper
}

List<VariableSuggestion> buildVariableSuggestions({
  required String query,
  required Iterable<String> userVariableNames, // env ∪ collection names
  required ResolvedVariable Function(String name) classify,
  bool includeDynamics = true,
});
```

- Candidate set = `userVariableNames` ∪ (curated dynamic names when
  `includeDynamics`). The curated dynamic list dedupes the
  `$randomUuid`/`$randomUUID` alias (show `$randomUUID`, `$guid`, `$timestamp`,
  `$isoTimestamp`, `$randomInt`).
- Filter case-insensitively by `query` (empty query → all). Ordering: prefix
  matches rank above substring matches; within a rank, user vars before
  dynamics, then alphabetical.
- Each surviving name is mapped through `classify` for its preview/secret/source.
  Because we only ever suggest known names, classification is never
  `unresolved`.

### 3. `lib/core/ui/widgets/variable_autocomplete.dart` (widget)

```dart
typedef VariableSuggestionsProvider =
    List<VariableSuggestion> Function(String query);

class VariableAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VariableSuggestionsProvider suggestionsFor;
  final Widget child; // the TextField
}
```

Responsibilities:
- Listen to `controller` (text + selection) → run `detectActiveVariableQuery`;
  open/close/refilter the menu. A `dismissed` latch (set by Esc) suppresses
  reopen until the text changes.
- Own one `OverlayEntry` anchored via a shared `LayerLink`
  (`CompositedTransformTarget` around `child`, `CompositedTransformFollower` in
  the overlay) at the field's bottom-left, so it follows scrolling inside the
  params/headers `ListView`. Mirrors the existing `VariableHoverController`
  overlay pattern.
- `Shortcuts`+`Actions` per the chosen approach. Intents: Next, Prev, Accept,
  Dismiss, Open. Accept/Next/Prev/Dismiss enabled only while open; Open always.
- Render the themed menu (`_VariableAutocompleteMenu`): selected-row highlight,
  source tag (active env name / `Collection` / `dynamic`), masked secret values
  (`••••`), dynamic sample values muted. All sizing/colors/radii via
  `context.appLayout/appPalette/appShape/appTypography/appDecoration`.

**Insertion on accept:** replace `text[replaceStart .. replaceEnd]` with
`name` + (`hasClosingBraces` ? `''` : `}}`); set the caret immediately after the
closing `}}`.

**Cmd/Ctrl+Space:** if a query is already active, (re)open the menu; otherwise
insert `{{` at the caret and let the controller listener open it.

## Modules — modified

### `lib/features/tabs/presentation/widgets/url_bar.dart`
Wrap the URL `TextField` (currently at the `Expanded` around line 229) with
`VariableAutocomplete`, passing `_urlController`, `_urlFocusNode`, and a
`suggestionsFor` closure. The closure reads live bloc state (as
`_showVariablePopover` already does): candidate names = active env var keys ∪
collected collection var keys; `classify` delegates to
`VariableResolutionHelper.classifyLayered` with the same layered inputs already
assembled there.

### `lib/core/ui/widgets/key_value_list_editor.dart`
- Add a per-row value `FocusNode` owned by `_KeyValueRowState` (value fields
  have none today), disposed with the row.
- When `variableContext != null` (and the value controller is a
  `VariableHighlightController`), wrap the value `TextField` with
  `VariableAutocomplete`. `suggestionsFor` builds names from
  `variableContext.variables.keys` and classifies via
  `VariableResolutionHelper.classify` (single-layer, matching the existing
  hover behavior for these fields).
- Thread the `suggestionsFor` provider from `_KeyValueListEditorState.build`
  (where `variableContext` is in scope) down to `_KeyValueRow`.

## Data flow

```
keystroke / caret move
  → controller listener
  → detectActiveVariableQuery(text, caret)         [pure]
  → suggestionsFor(query)
      → buildVariableSuggestions(...)              [pure]
          → classify(name) via VariableResolutionHelper
  → open/refilter overlay menu
  → ↑/↓ change selection; Enter/Tab/click accept
  → replace query span with `name}}`, move caret
  → controller text changes → existing onChanged → bloc update (unchanged)
```

The existing URL `onChanged` (cURL-paste detection, bloc update) and the
existing highlight/hover behavior are untouched and run alongside.

## Edge cases

- Empty query (just `{{` or Cmd/Ctrl+Space): show all candidates.
- No matches: hide the menu (Cmd/Ctrl+Space with zero env+collection vars still
  shows dynamics, so this is rare).
- Non-collapsed selection: no menu.
- A space/`/`/other non-identifier char between `{{` and caret ends the token →
  menu closes.
- Secret value rows (`obscureText`) still get autocomplete (user may reference
  another variable); harmless.
- Esc latch: dismissing does not immediately reopen on the same text; the next
  text change clears the latch.

## Theming

Menu chrome via `context.appDecoration.panelBox` + `context.appShape`
(`panelRadius`/`dialogRadius`); selected-row and source-tag colors from
`context.appPalette` (`variableResolved`/`variableUnresolved`) and the
`colorScheme`; text weights/sizes from `context.appTypography`/`appLayout`. No
hardcoded sizes/colors/radii (CLAUDE.md §4.8/§6).

## Testing (TDD)

**Pure unit tests**
- `detectActiveVariableQuery`: caret after `{{`, partial name, `}}` already
  present, invalid char ends token, single `{`, no token, caret before braces,
  nested/sequential tokens, non-collapsed selection.
- `buildVariableSuggestions`: empty-query returns all; case-insensitive filter;
  prefix-before-substring ordering; user-vars-before-dynamics; dynamic
  dedupe; `includeDynamics: false`; classification + secret mapping.

**Widget tests** (`VariableAutocomplete` in a minimal harness)
- Typing `{{` opens the menu; typing filters.
- ↑/↓ + Enter inserts `name}}` with the caret after `}}`.
- Tab accepts; click accepts; Esc closes (and does not reopen until text
  changes); focus loss closes.
- Cmd/Ctrl+Space opens the menu.

**Integration widget tests**
- The URL bar surfaces the menu and inserts on accept.
- A params/headers value field surfaces the menu and inserts on accept.

## Verification bar (per CLAUDE.md §5)

`fvm flutter analyze` (very_good_analysis) + `fvm dart run custom_lint` +
`fvm dart run bloc_tools:bloc lint lib` all clean, `fvm dart format` clean, and
`fvm flutter test` 100% green. No `@HiveType` changes → no `build_runner`.

## Wiki

User-facing change (new behavior) → update the relevant page in the
`Getman.wiki.git` repo (variables / environments page) describing the
autocomplete trigger and keys, per the CLAUDE.md "Keep the wiki in sync"
mandate.

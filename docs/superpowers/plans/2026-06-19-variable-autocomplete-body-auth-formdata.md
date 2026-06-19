# Variable Autocomplete on Body, Auth & Form-Data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `{{var}}` autocomplete, color highlighting, and hover preview to the request body (raw/JSON), auth fields, and form-data values — sourcing env + collection + dynamic variables everywhere, and aligning params/headers to that same source set.

**Architecture:** Introduce one variable-source value object (`LayeredVariableContext`) and one builder widget (`TabVariableContextBuilder`) that feeds it from live bloc state. A new `VariableTextField` atom bundles the existing highlight-controller + autocomplete-overlay + hover wiring for every plain `TextField` (auth, form-data, kv editor). The `re_editor` body uses the package's built-in `CodeAutocomplete` with a custom prompts-builder + a variable-aware JSON span builder + a hover overlay.

**Tech Stack:** Flutter, `flutter_bloc`, `re_editor 0.9.0` (built-in `CodeAutocomplete`), `re_highlight`, existing Getman variable utilities.

## Global Constraints

- Flutter SDK is pinned via `.fvmrc` — invoke every command as `fvm flutter ...` / `fvm dart ...`, never plain `flutter`/`dart`.
- All imports are `package:getman/...` (no relative imports; enforced by `always_use_package_imports` + `directives_ordering`).
- No hardcoded sizes/colors/radii/weights — pull from `context.appLayout` / `appPalette` / `appShape` / `appTypography` / `appDecoration`. Variable token colors are `appPalette.variableResolved` / `variableUnresolved`.
- Do **not** reach `sl<T>()`/`GetIt` from widgets (custom_lint `avoid_get_it_in_widgets`); read services/blocs via `context.read`/`BlocBuilder`/`RepositoryProvider`.
- Do **not** set `CodeEditorStyle.codeTheme` on the body editor — JSON coloring stays in the span builder (CLAUDE.md gotcha).
- Domain layer stays pure; this is all presentation/util layer — no Hive/Dio/bloc/event/state changes, no new `@HiveType`.
- Done-bar before any task is "complete": `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0 issues), `fvm dart run bloc_tools:bloc lint lib` (0 issues), `fvm dart format lib test tools` clean, `fvm flutter test` green. The three analysis passes are independent.
- Reference spec: `docs/superpowers/specs/2026-06-19-variable-autocomplete-body-auth-formdata-design.md`.

---

## File Structure

**Create:**
- `lib/core/utils/layered_variable_context.dart` — `LayeredVariableContext` value object (env+collection layers + dynamics; `classify`, merged getters).
- `lib/core/ui/widgets/tab_variable_context_builder.dart` — `TabVariableContextBuilder` widget (builds the context from blocs for a tab).
- `lib/core/ui/widgets/variable_text_field.dart` — `VariableTextField` atom (highlight + autocomplete + hover over a caller-owned controller).
- `lib/features/tabs/presentation/widgets/variable_code_autocomplete.dart` — body editor: `VariablePromptsBuilder`, `_VariableCodePrompt`, `variableAutocompleteViewBuilder`, `wrapBodyWithVariableAutocomplete(...)`.
- `lib/features/tabs/presentation/widgets/variable_json_span_builder.dart` — variable-aware JSON span builder (flat-run merge).
- Tests mirroring each (under `test/...` following the existing test tree).

**Modify:**
- `lib/core/ui/widgets/key_value_list_editor.dart` — swap `VariableHoverContext?` → `LayeredVariableContext?`, render value field via `VariableTextField`, delete inline wiring.
- `lib/features/tabs/presentation/widgets/request_editor_tabs.dart` — replace private `_VariableContextBuilder` usage with the shared `TabVariableContextBuilder`; pass `LayeredVariableContext`.
- `lib/features/tabs/presentation/widgets/auth_tab_view.dart` — `_field` uses `VariableTextField`; wrap field list in `TabVariableContextBuilder`.
- `lib/features/tabs/presentation/widgets/form_data_editor.dart` — value field uses `VariableTextField`; wrap in `TabVariableContextBuilder`.
- `lib/features/tabs/presentation/widgets/json_code_editor.dart` — accept an optional variables source; use the variable-aware span builder.
- `lib/features/tabs/presentation/widgets/request_view.dart` (+ `request_editor_tabs.dart` `BodyTabView`/`_RawBodyEditor`) — wrap the raw body `CodeEditor` in the variable autocomplete + feed it the tab context.

---

## Task 1: `LayeredVariableContext` value object

**Files:**
- Create: `lib/core/utils/layered_variable_context.dart`
- Test: `test/core/utils/layered_variable_context_test.dart`

**Interfaces:**
- Consumes: `VariableResolutionHelper.classifyLayered` + `ResolvedVariable` (`lib/core/utils/variable_resolution_helper.dart`), `EnvironmentResolver.isDynamic`.
- Produces:
  - `class LayeredVariableContext` with const ctor `({Map<String,String> environmentVariables, Set<String> environmentSecrets, Map<String,String> collectionVariables, Set<String> collectionSecrets, String? environmentName})` (all default to empty/null).
  - `Map<String,String> get allVariables` — collection overlaid by env (env wins).
  - `Set<String> get allSecretKeys` — union of both secret sets.
  - `bool get isEmpty` — true when `allVariables` is empty.
  - `ResolvedVariable classify(String name)` — delegates to `classifyLayered`.
  - `static const empty = LayeredVariableContext()`.
  - Equatable.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/layered_variable_context_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

void main() {
  group('LayeredVariableContext', () {
    const ctx = LayeredVariableContext(
      environmentVariables: {'host': 'env.example.com', 'token': 'secret'},
      environmentSecrets: {'token'},
      collectionVariables: {'host': 'col.example.com', 'path': '/v1'},
      collectionSecrets: {},
      environmentName: 'Staging',
    );

    test('allVariables merges with environment winning', () {
      expect(ctx.allVariables['host'], 'env.example.com'); // env wins
      expect(ctx.allVariables['path'], '/v1'); // collection-only kept
      expect(ctx.allVariables.keys, containsAll(['host', 'token', 'path']));
    });

    test('allSecretKeys unions both layers', () {
      expect(ctx.allSecretKeys, contains('token'));
    });

    test('classify reports environment source and secret kind', () {
      final t = ctx.classify('token');
      expect(t.kind, VariableValueKind.secret);
      expect(t.environmentName, 'Staging');
    });

    test('classify reports Collection source for collection-only var', () {
      final p = ctx.classify('path');
      expect(p.kind, VariableValueKind.resolved);
      expect(p.environmentName, 'Collection');
    });

    test('classify resolves dynamics and marks unknown unresolved', () {
      expect(ctx.classify(r'$guid').kind, VariableValueKind.dynamicValue);
      expect(ctx.classify('nope').kind, VariableValueKind.unresolved);
    });

    test('empty context isEmpty', () {
      expect(LayeredVariableContext.empty.isEmpty, isTrue);
      expect(ctx.isEmpty, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/layered_variable_context_test.dart`
Expected: FAIL — `layered_variable_context.dart` does not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/utils/layered_variable_context.dart
import 'package:equatable/equatable.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

/// The full set of variables available to a request field: the active
/// environment layered over the request's inherited collection variables
/// (environment wins on conflict), plus dynamic built-ins via [classify].
/// Pure Dart — the single currency passed to every variable-aware field.
class LayeredVariableContext extends Equatable {
  const LayeredVariableContext({
    this.environmentVariables = const {},
    this.environmentSecrets = const {},
    this.collectionVariables = const {},
    this.collectionSecrets = const {},
    this.environmentName,
  });

  static const LayeredVariableContext empty = LayeredVariableContext();

  final Map<String, String> environmentVariables;
  final Set<String> environmentSecrets;
  final Map<String, String> collectionVariables;
  final Set<String> collectionSecrets;
  final String? environmentName;

  /// Collection overlaid by environment (environment wins). Used for token
  /// highlighting (resolved-vs-not) and as the autocomplete candidate set.
  Map<String, String> get allVariables => {
    ...collectionVariables,
    ...environmentVariables,
  };

  Set<String> get allSecretKeys => {...collectionSecrets, ...environmentSecrets};

  bool get isEmpty => allVariables.isEmpty;

  ResolvedVariable classify(String name) =>
      VariableResolutionHelper.classifyLayered(
        name: name,
        collectionVariables: collectionVariables,
        collectionSecrets: collectionSecrets,
        environmentVariables: environmentVariables,
        environmentSecrets: environmentSecrets,
        environmentName: environmentName,
      );

  @override
  List<Object?> get props => [
    environmentVariables,
    environmentSecrets,
    collectionVariables,
    collectionSecrets,
    environmentName,
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/layered_variable_context_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Analyze + format + commit**

```bash
fvm flutter analyze lib/core/utils/layered_variable_context.dart
fvm dart format lib/core/utils/layered_variable_context.dart test/core/utils/layered_variable_context_test.dart
git add lib/core/utils/layered_variable_context.dart test/core/utils/layered_variable_context_test.dart
git commit -m "feat(variables): add LayeredVariableContext value object"
```

---

## Task 2: `TabVariableContextBuilder` widget

Builds a `LayeredVariableContext` for a given tab from live `EnvironmentsBloc` + `SettingsBloc` + `CollectionsBloc` + `TabsBloc` state, rebuilding when the env set / active-env id / collection tree change. This is the shared replacement for the private env-only `_VariableContextBuilder` in `request_editor_tabs.dart`.

**Files:**
- Create: `lib/core/ui/widgets/tab_variable_context_builder.dart`
- Test: `test/core/ui/widgets/tab_variable_context_builder_test.dart`

**Interfaces:**
- Consumes: `LayeredVariableContext` (Task 1); `ActiveEnvironmentHelper.activeEnvironment`; `CollectionsTreeHelper.collectVariables`; blocs `EnvironmentsBloc`/`EnvironmentsState`, `SettingsBloc`/`SettingsState`, `CollectionsBloc`/`CollectionsState`, `TabsBloc`/`TabsState` (+ `TabsState.tabs.byId`).
- Produces: `class TabVariableContextBuilder extends StatelessWidget` with ctor `({required String tabId, required Widget Function(BuildContext, LayeredVariableContext) builder, Key? key})`.

> Mirror the existing `_layeredContext()` reads in `url_bar.dart:129` exactly (env active environment + `tab.collectionNodeId` → `CollectionsTreeHelper.collectVariables`). Wrap in nested `BlocBuilder`s with narrow `buildWhen`: SettingsBloc on `activeEnvironmentId`, EnvironmentsBloc on `environments`, CollectionsBloc on `collections`, TabsBloc on the tab's `collectionNodeId`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/widgets/tab_variable_context_builder_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
// Import the project's blocs + states + entities and the test helpers used by
// the existing url_bar/request_editor_tabs widget tests. Reuse those fakes.

void main() {
  testWidgets('exposes env + collection layered context for the tab', (
    tester,
  ) async {
    // Arrange: pump TabVariableContextBuilder under MultiBlocProvider with
    //   - an active environment {host: env} (id selected in settings)
    //   - a collection node (tab.collectionNodeId) carrying {path: /v1}
    // Capture the LayeredVariableContext yielded to the builder.
    late LayeredVariableContext captured;
    // ... pump with fakes (see existing request_editor_tabs_test.dart setup) ...
    // builder: (_, ctx) { captured = ctx; return const SizedBox(); }

    expect(captured.environmentVariables['host'], isNotNull);
    expect(captured.collectionVariables['path'], '/v1');
    expect(captured.allVariables.keys, containsAll(['host', 'path']));
  });
}
```

> **Implementer note:** copy the bloc/fake setup from the nearest existing widget test that already provides EnvironmentsBloc + SettingsBloc + CollectionsBloc + TabsBloc (search `test/` for `_VariableContextBuilder` coverage or `request_editor_tabs_test`). Do not invent a new harness.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/tab_variable_context_builder_test.dart`
Expected: FAIL — `tab_variable_context_builder.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/widgets/tab_variable_context_builder.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Builds the layered (environment + collection + dynamic) variable context
/// for [tabId] from live bloc state, rebuilding when the active environment,
/// the environment set, the collection tree, or the tab's linked node change.
/// Shared by params, headers, auth, form-data, and the body editor so every
/// field offers identical suggestions.
class TabVariableContextBuilder extends StatelessWidget {
  const TabVariableContextBuilder({
    required this.tabId,
    required this.builder,
    super.key,
  });

  final String tabId;
  final Widget Function(BuildContext, LayeredVariableContext) builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
      builder: (context, settingsState) {
        return BlocBuilder<EnvironmentsBloc, EnvironmentsState>(
          buildWhen: (p, n) => p.environments != n.environments,
          builder: (context, envState) {
            return BlocBuilder<TabsBloc, TabsState>(
              buildWhen: (p, n) =>
                  p.tabs.byId(tabId)?.collectionNodeId !=
                  n.tabs.byId(tabId)?.collectionNodeId,
              builder: (context, tabsState) {
                return BlocBuilder<CollectionsBloc, CollectionsState>(
                  buildWhen: (p, n) => p.collections != n.collections,
                  builder: (context, collectionsState) {
                    final env = ActiveEnvironmentHelper.activeEnvironment(
                      envState.environments,
                      settingsState.settings.activeEnvironmentId,
                    );
                    final nodeId = tabsState.tabs.byId(tabId)?.collectionNodeId;
                    final collected = nodeId == null
                        ? (
                            variables: const <String, String>{},
                            secretKeys: const <String>{},
                          )
                        : CollectionsTreeHelper.collectVariables(
                            collectionsState.collections,
                            nodeId,
                          );
                    return builder(
                      context,
                      LayeredVariableContext(
                        environmentVariables: env?.variables ?? const {},
                        environmentSecrets: env?.secretKeys ?? const {},
                        collectionVariables: collected.variables,
                        collectionSecrets: collected.secretKeys,
                        environmentName: env?.name,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
```

> Verify `CollectionsTreeHelper.collectVariables` returns a record with `.variables` and `.secretKeys` (it does — see `url_bar.dart:139`). Verify `TabsState.tabs.byId(...)` exists (it does — `url_bar.dart:137`).

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/tab_variable_context_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format + commit**

```bash
fvm flutter analyze lib/core/ui/widgets/tab_variable_context_builder.dart
fvm dart format lib/core/ui/widgets/tab_variable_context_builder.dart test/core/ui/widgets/tab_variable_context_builder_test.dart
git add lib/core/ui/widgets/tab_variable_context_builder.dart test/core/ui/widgets/tab_variable_context_builder_test.dart
git commit -m "feat(variables): add shared TabVariableContextBuilder"
```

---

## Task 3: `VariableTextField` atom

A drop-in `TextField` that highlights `{{var}}`, shows the `{{`-autocomplete overlay, and shows the hover popover — given a `LayeredVariableContext` and a caller-owned `VariableHighlightController`. This is the extraction of the wiring currently inlined in `KeyValueListEditor` (`key_value_list_editor.dart:181-206`, `:352-360`).

**Files:**
- Create: `lib/core/ui/widgets/variable_text_field.dart`
- Test: `test/core/ui/widgets/variable_text_field_test.dart`

**Interfaces:**
- Consumes: `LayeredVariableContext` (Task 1); `VariableHighlightController`, `VariableAutocomplete`, `VariableHoverController`, `buildVariableSuggestions`.
- Produces: `class VariableTextField extends StatefulWidget` with ctor:
  ```dart
  const VariableTextField({
    required this.context_, // LayeredVariableContext  (named `variables` below)
    required this.controller,        // VariableHighlightController (caller-owned)
    required this.focusNode,         // FocusNode (caller-owned)
    required this.onChanged,         // ValueChanged<String>
    this.decoration,                 // InputDecoration?
    this.obscureText = false,
    this.fieldKey,                   // Key? applied to the inner TextField
    super.key,
  });
  ```
  (Use a clean param name — `variables` of type `LayeredVariableContext` — not `context_`. The owner keeps the controller so existing echo-suppression keeps working.)

> **Why caller-owned controller:** auth/form-data/kv all hold their own controllers and suppress echoes across the bloc round-trip; the atom only decorates. Assert/require a `VariableHighlightController` so `buildTextSpan` highlighting works.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/widgets/variable_text_field_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_text_field.dart';
import 'package:getman/core/utils/layered_variable_context.dart';

Widget _host(Widget child) => MaterialApp(
  theme: resolveTheme('brutalist')(Brightness.light, false),
  home: Scaffold(body: child),
);

void main() {
  const ctx = LayeredVariableContext(
    environmentVariables: {'host': 'example.com', 'token': 'abc'},
    environmentName: 'Staging',
  );

  testWidgets('typing {{ opens the suggestion overlay', (tester) async {
    final controller = VariableHighlightController();
    final focus = FocusNode();
    await tester.pumpWidget(
      _host(
        VariableTextField(
          variables: ctx,
          controller: controller,
          focusNode: focus,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();

    expect(find.text('host'), findsOneWidget);
    expect(find.text('token'), findsOneWidget);
  });

  testWidgets('accepting a suggestion inserts {{name}}', (tester) async {
    final controller = VariableHighlightController();
    final focus = FocusNode();
    await tester.pumpWidget(
      _host(
        VariableTextField(
          variables: ctx,
          controller: controller,
          focusNode: focus,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '{{ho');
    await tester.pumpAndSettle();
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();

    expect(controller.text, '{{host}}');
  });

  testWidgets('empty context renders a plain field with no overlay', (
    tester,
  ) async {
    final controller = VariableHighlightController();
    final focus = FocusNode();
    await tester.pumpWidget(
      _host(
        VariableTextField(
          variables: LayeredVariableContext.empty,
          controller: controller,
          focusNode: focus,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    // No suggestions to show.
    expect(find.byType(ListView), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/variable_text_field_test.dart`
Expected: FAIL — `variable_text_field.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/widgets/variable_text_field.dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/variable_suggestions.dart';
import 'package:getman/core/utils/layered_variable_context.dart';

/// A [TextField] that highlights `{{var}}` tokens, offers a `{{`-triggered
/// autocomplete overlay, and shows a hover popover resolving each token —
/// given a [variables] context and a caller-owned [VariableHighlightController]
/// (kept by the owner so its echo-suppression survives the bloc round-trip).
/// When [variables] is empty it degrades to a plain styled field.
class VariableTextField extends StatefulWidget {
  const VariableTextField({
    required this.variables,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.decoration,
    this.obscureText = false,
    this.fieldKey,
    super.key,
  });

  final LayeredVariableContext variables;
  final VariableHighlightController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final bool obscureText;
  final Key? fieldKey;

  @override
  State<VariableTextField> createState() => _VariableTextFieldState();
}

class _VariableTextFieldState extends State<VariableTextField> {
  final VariableHoverController _hover = VariableHoverController();

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  void _showPopover(String name, Offset globalPosition) {
    if (!mounted) return;
    _hover.showFor(context, widget.variables.classify(name), globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final ctx = widget.variables;

    // Wire highlight colors + variable map + hover sinks onto the controller.
    widget.controller
      ..updateColors(
        resolved: palette.variableResolved,
        unresolved: palette.variableUnresolved,
      )
      ..updateVariables(ctx.allVariables)
      ..onVariableEnter = ctx.isEmpty
          ? null
          : (name, pos) {
              _showPopover(name, pos);
            }
      ..onVariableExit = ctx.isEmpty ? null : _hover.scheduleHide;

    final field = TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      obscureText: widget.obscureText,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
    );

    if (ctx.isEmpty) return field;

    return VariableAutocomplete(
      controller: widget.controller,
      focusNode: widget.focusNode,
      suggestionsFor: (query) => buildVariableSuggestions(
        query: query,
        userVariableNames: ctx.allVariables.keys,
        classify: ctx.classify,
      ),
      onAccepted: widget.onChanged,
      child: field,
    );
  }
}
```

> `obscureText: true` + a `VariableHighlightController` still shows the overlay; the field obscures characters but the menu works (matches the design's "password autocompletes while obscured"). Note `enableSuggestions/autocorrect` are forced off, as elsewhere.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/variable_text_field_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze + format + commit**

```bash
fvm flutter analyze lib/core/ui/widgets/variable_text_field.dart
fvm dart format lib/core/ui/widgets/variable_text_field.dart test/core/ui/widgets/variable_text_field_test.dart
git add lib/core/ui/widgets/variable_text_field.dart test/core/ui/widgets/variable_text_field_test.dart
git commit -m "feat(variables): add VariableTextField atom"
```

---

## Task 4: Migrate `KeyValueListEditor` + params/headers to the layered context

Switch the kv editor's `variableContext` from `VariableHoverContext?` to `LayeredVariableContext?`, render the value field via `VariableTextField`, and delete the inline highlight/hover/suggestion wiring. Update `request_editor_tabs.dart` to feed params/headers through `TabVariableContextBuilder` (so they gain collection + dynamic suggestions — the approved behavior change). Remove the now-unused private `_VariableContextBuilder` and, if it becomes unreferenced, `VariableHoverContext`.

**Files:**
- Modify: `lib/core/ui/widgets/key_value_list_editor.dart`
- Modify: `lib/features/tabs/presentation/widgets/request_editor_tabs.dart`
- Test: `test/core/ui/widgets/key_value_list_editor_test.dart` (existing — extend), `test/features/tabs/presentation/widgets/request_editor_tabs_test.dart` (existing — adjust)

**Interfaces:**
- Consumes: `VariableTextField` (Task 3), `LayeredVariableContext` (Task 1), `TabVariableContextBuilder` (Task 2).
- Produces: `KeyValueListEditor<T>` now takes `LayeredVariableContext? variableContext`. The `_KeyValueRow` value field becomes a `VariableTextField` when context is non-empty; the prior `valueSuggestionsFor` / inline `VariableHighlightController` wiring is removed.

- [ ] **Step 1: Update the existing kv editor test to the new type**

In `test/core/ui/widgets/key_value_list_editor_test.dart`, change any `VariableHoverContext(...)` passed as `variableContext:` to `LayeredVariableContext(environmentVariables: {...}, environmentName: ...)`. Add an assertion that a `{{` in a value field opens the overlay (find a suggestion name), mirroring Task 3's first test. Keep all existing non-variable kv tests unchanged.

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/key_value_list_editor_test.dart`
Expected: FAIL — `KeyValueListEditor.variableContext` still typed `VariableHoverContext?` (compile error on the new `LayeredVariableContext`).

- [ ] **Step 3: Implement — kv editor**

In `key_value_list_editor.dart`:
1. Change the field + ctor param:
   ```dart
   final LayeredVariableContext? variableContext;
   ```
   Update the doc comment to say "the layered (env + collection + dynamic) context".
2. `_newValueController` keeps returning `VariableHighlightController` when `variableContext != null` (a non-null but empty context still gets a highlight controller; `VariableTextField` degrades gracefully).
3. In `build`, delete the whole `if (varContext != null && valController is VariableHighlightController) { ... }` block (the inline `updateColors`/`updateVariables`/`onVariableEnter`/`valueSuggestionsFor` setup) and the `_showVariablePopover`/`_hoverController` machinery if now unused — `VariableTextField` owns all of it.
4. Pass the context down to the row instead of `valueSuggestionsFor`:
   ```dart
   return _KeyValueRow(
     ...,
     variableContext: widget.variableContext,
     ...,
   );
   ```
5. In `_KeyValueRow`, replace `valueSuggestionsFor` with `final LayeredVariableContext? variableContext;` and build the value field as:
   ```dart
   final valController = widget.valController;
   final ctx = widget.variableContext;
   final valueFieldWithAutocomplete =
       (ctx == null || ctx.isEmpty || valController is! VariableHighlightController)
       ? valueField
       : VariableTextField(
           variables: ctx,
           controller: valController,
           focusNode: _valueFocusNode,
           onChanged: widget.onValChanged,
           decoration: /* the existing valueField decoration */,
           fieldKey: /* existing ValueKey('<prefix>_val_<index>') if any */,
         );
   ```
   Simplest: keep `valueField` for the plain case and only wrap with `VariableTextField` for the variable case. To avoid building the field twice, factor the `InputDecoration` into a local and pass it to `VariableTextField`. (The reveal/secret toggle suffix logic stays on the plain `valueField`; secret rows are env-editor-only and pass a null `variableContext`, so the two never combine.)

> Keep `import 'variable_text_field.dart'`; drop now-unused imports (`variable_autocomplete.dart`, `variable_hover_popover.dart`, `variable_suggestions.dart`, `variable_resolution_helper.dart`) if no longer referenced — `fvm flutter analyze` will flag leftovers.

- [ ] **Step 4: Implement — params/headers wiring**

In `request_editor_tabs.dart`:
1. Replace the private `_VariableContextBuilder` (lines ~37-71) — delete it.
2. At the params usage (~line 194) and headers usage (~line 275), wrap with the shared builder:
   ```dart
   TabVariableContextBuilder(
     tabId: tab.tabId, // or the tabId in scope
     builder: (context, varContext) => KeyValueListEditor<...>(
       items: ...,
       variableContext: varContext,
       fieldPrefix: 'param', // 'header' for headers
       decode: ...,
       encode: ...,
       equals: ...,
       onChanged: emit,
     ),
   )
   ```
3. Remove the now-unused imports that only `_VariableContextBuilder` needed (`active_environment_helper`, `variable_hover_popover`'s `VariableHoverContext`, the env/settings bloc imports if unused elsewhere in the file). Add the `tab_variable_context_builder.dart` + `layered_variable_context.dart` imports.

- [ ] **Step 5: Run tests to verify they pass**

Run: `fvm flutter test test/core/ui/widgets/key_value_list_editor_test.dart test/features/tabs/presentation/widgets/request_editor_tabs_test.dart`
Expected: PASS. Fix any test that asserted env-only suggestions to also accept collection/dynamic names.

- [ ] **Step 6: Full analyze (dead-code check) + format + commit**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart format lib test
git add lib/core/ui/widgets/key_value_list_editor.dart lib/features/tabs/presentation/widgets/request_editor_tabs.dart test/core/ui/widgets/key_value_list_editor_test.dart test/features/tabs/presentation/widgets/request_editor_tabs_test.dart
git commit -m "refactor(variables): kv editor + params/headers use layered context via VariableTextField"
```

> If `VariableHoverContext` is now unreferenced anywhere, delete it from `variable_hover_popover.dart` in this commit (analyze will confirm). If still referenced, leave it.

---

## Task 5: Auth fields

Wrap the auth field list in `TabVariableContextBuilder` and render each field via `VariableTextField`. Field controllers become `VariableHighlightController` (still caller-owned, echo-suppression unchanged).

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/auth_tab_view.dart`
- Test: `test/features/tabs/presentation/widgets/auth_tab_view_test.dart` (create if absent)

**Interfaces:**
- Consumes: `VariableTextField`, `LayeredVariableContext`, `TabVariableContextBuilder`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/tabs/presentation/widgets/auth_tab_view_test.dart
// Pump AuthTabView(tabId: ...) under the bloc harness used by other tabs
// widget tests (provides TabsBloc/EnvironmentsBloc/SettingsBloc/CollectionsBloc),
// with an active environment {host: example.com} and the tab's auth = bearer.
//
// 1. Tap the TOKEN field, enterText '{{ho', pumpAndSettle.
// 2. expect(find.text('host'), findsOneWidget);  // suggestion overlay
// 3. tap it; expect the token field controller text == '{{host}}'.
```

> Reuse the existing tabs widget-test harness (search `test/features/tabs/.../*auth*` or the request panel tests for the provider setup).

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/auth_tab_view_test.dart`
Expected: FAIL — no overlay (auth fields are plain `TextField`s).

- [ ] **Step 3: Implement**

In `auth_tab_view.dart`:
1. Change the five controllers to `VariableHighlightController`:
   ```dart
   late final VariableHighlightController _token;
   // ...same for _username, _password, _apiKeyName, _apiKeyValue
   _token = VariableHighlightController(text: auth.token);
   ```
2. Add a `FocusNode` per field (auth currently has none) — `late final FocusNode _tokenFocus; ...` created in `initState`, disposed in `dispose`. (Or a `Map<TextEditingController, FocusNode>`.)
3. Wrap the built field column in `build` with the context builder. Since `_fieldsFor`/`_field` need the context, thread it in:
   ```dart
   @override
   Widget build(BuildContext context) {
     return TabVariableContextBuilder(
       tabId: widget.tabId,
       builder: (context, varContext) => Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           // ... existing type selector ...
           ..._fieldsFor(context, varContext),
         ],
       ),
     );
   }
   ```
4. `_field(...)` gains a `LayeredVariableContext` + `FocusNode` and returns a `VariableTextField`:
   ```dart
   Widget _field(
     BuildContext context,
     String label,
     VariableHighlightController controller,
     FocusNode focusNode,
     LayeredVariableContext variables, {
     bool obscure = false,
   }) {
     return Padding(
       // keep the existing label + spacing layout around it
       child: VariableTextField(
         fieldKey: ValueKey('auth_field_$label'),
         variables: variables,
         controller: controller,
         focusNode: focusNode,
         obscureText: obscure,
         onChanged: (_) => _emit(),
         decoration: /* the existing auth field InputDecoration */,
       ),
     );
   }
   ```
   Preserve the existing label widget and `InputDecoration` exactly; only the inner `TextField` becomes `VariableTextField`. Keep `_setIfChanged`/`_lastEmitted` echo-suppression and `_emit` unchanged.

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/features/tabs/presentation/widgets/auth_tab_view_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + bloc-lint + format + commit**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart format lib test
git add lib/features/tabs/presentation/widgets/auth_tab_view.dart test/features/tabs/presentation/widgets/auth_tab_view_test.dart
git commit -m "feat(variables): variable autocomplete on auth fields"
```

---

## Task 6: Form-data values

Wrap the form-data editor in `TabVariableContextBuilder`; the non-file value field becomes a `VariableTextField` over a `VariableHighlightController` value controller.

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/form_data_editor.dart`
- Test: `test/features/tabs/presentation/widgets/form_data_editor_test.dart` (create if absent)

**Interfaces:**
- Consumes: `VariableTextField`, `LayeredVariableContext`, `TabVariableContextBuilder`.

- [ ] **Step 1: Write the failing test**

```dart
// Pump FormDataEditor(tabId: ..., allowFiles: true) under the tabs harness
// with active environment {host: example.com} and one urlencoded/multipart row.
// 1. enterText '{{ho' into the value field of a non-file row; pumpAndSettle.
// 2. expect(find.text('host'), findsOneWidget);
// 3. tap it; expect that row's valueController text == '{{host}}'.
// 4. (negative) the NAME field shows no overlay for '{{'.
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/form_data_editor_test.dart`
Expected: FAIL — value field is a plain `TextField`.

- [ ] **Step 3: Implement**

In `form_data_editor.dart`:
1. Change `_RowState.valueController` to `VariableHighlightController` (both factory constructors at lines ~303-313). Add a `FocusNode valueFocus` per row (created in the row factories, disposed in `_RowState.dispose` alongside `valueController.dispose()`).
2. Wrap the editor body (`build`, ~line 112) in `TabVariableContextBuilder(tabId: widget.tabId, builder: (context, varContext) => ...)` and thread `varContext` to the row builder.
3. Replace the non-file value `TextField` (~line 175) with:
   ```dart
   : VariableTextField(
       fieldKey: ValueKey('val_${row.id}'),
       variables: varContext,
       controller: row.valueController, // VariableHighlightController
       focusNode: row.valueFocus,
       onChanged: (_) => _emit(),
       decoration: /* the existing value-field InputDecoration */,
     )
   ```
   File rows (`_FilePickButton`) and the name `TextField` are unchanged. `_emit` flow unchanged.

> If `_emit` reads `valueController.text`, it still works — `VariableHighlightController` is a `TextEditingController`.

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/features/tabs/presentation/widgets/form_data_editor_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format + commit**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart format lib test
git add lib/features/tabs/presentation/widgets/form_data_editor.dart test/features/tabs/presentation/widgets/form_data_editor_test.dart
git commit -m "feat(variables): variable autocomplete on form-data values"
```

---

## Task 7: Body editor — autocomplete via `re_editor` `CodeAutocomplete`

Add a `{{`-triggered variable autocomplete to the raw/JSON body editor using `re_editor 0.9.0`'s built-in `CodeAutocomplete`, reusing `detectActiveVariableQuery` + `buildVariableSuggestions`.

**Files:**
- Create: `lib/features/tabs/presentation/widgets/variable_code_autocomplete.dart`
- Modify: `lib/features/tabs/presentation/widgets/json_code_editor.dart` (optional wrap), `lib/features/tabs/presentation/widgets/request_editor_tabs.dart` (`_RawBodyEditor`), and `request_view.dart` (provide the tab context to the body editor)
- Test: `test/features/tabs/presentation/widgets/variable_code_autocomplete_test.dart`

**Interfaces:**
- Consumes: `re_editor` (`CodeAutocomplete`, `CodeAutocompletePromptsBuilder`, `CodeAutocompleteEditingValue`, `CodePrompt`, `CodeAutocompleteResult`, `CodeLine`, `CodeLineSelection`); `detectActiveVariableQuery`/`ActiveVariableQuery`; `buildVariableSuggestions`/`VariableSuggestion`; `LayeredVariableContext`.
- Produces:
  - `class VariablePromptsBuilder implements CodeAutocompletePromptsBuilder` — ctor `(LayeredVariableContext Function() contextProvider)` (read live so env switches apply). `build(context, codeLine, selection)` → `CodeAutocompleteEditingValue?`.
  - `Widget wrapBodyWithVariableAutocomplete({required LayeredVariableContext Function() contextProvider, required Widget child})` returning a `CodeAutocomplete` (returns `child` unchanged when the context provider yields empty, to avoid an empty overlay).
  - `CodeAutocompleteWidgetBuilder variableAutocompleteViewBuilder` — the themed suggestion list.

**Verified `re_editor` mechanics (from lib source):**
- `_updateAutoCompleteState` calls `promptsBuilder.build(...)` on every line-changing keystroke when the selection is collapsed.
- On select, the editor runs `controller.replaceSelection(word, range=[caret - input.length, caret])` then moves the caret by `word.length - input.length`. So set `input = query.query` (chars after `{{`) and `word = name` (+ `}}` when `!hasClosingBraces`); the `{{` stays, caret lands after the insert.
- Nav ↑/↓ + Enter are handled by the package's actions; Tab is **not** wired (documented divergence).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/tabs/presentation/widgets/variable_code_autocomplete_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/tabs/presentation/widgets/variable_code_autocomplete.dart';

void main() {
  const ctx = LayeredVariableContext(
    environmentVariables: {'host': 'example.com', 'token': 'abc'},
    environmentName: 'Staging',
  );

  group('VariablePromptsBuilder.build', () {
    final builder = VariablePromptsBuilder(() => ctx);

    CodeAutocompleteEditingValue? run(String line, int caret) => builder.build(
      // A minimal BuildContext is not needed by build(); pass a dummy via a
      // pumped widget if the impl reads context. If it doesn't, refactor build
      // to not require context and test directly. Prefer a pumped Builder.
      _ctx!,
      CodeLine(line),
      CodeLineSelection.collapsed(index: 0, offset: caret),
    );

    // Implementer: if build needs BuildContext only for theme, keep detection
    // logic in a pure helper and unit-test THAT helper here instead:
    //   variablePromptsFor(ctx, line, caret) -> ({String input, List<VariableSuggestion> suggestions})?
    test('returns suggestions for an open {{ token', () {
      final r = variablePromptsFor(ctx, '{{ho', 4);
      expect(r, isNotNull);
      expect(r!.input, 'ho');
      expect(r.suggestions.map((s) => s.name), contains('host'));
    });

    test('returns null when caret is not in a {{ token', () {
      expect(variablePromptsFor(ctx, 'plain text', 5), isNull);
    });

    test('word includes closing braces when not already present', () {
      // For query 'ho' with no following }}, accepting 'host' must yield
      // an insertion word of 'host}}'.
      final word = variableInsertionWord('host', hasClosingBraces: false);
      expect(word, 'host}}');
      expect(variableInsertionWord('host', hasClosingBraces: true), 'host');
    });
  });
}

CodeAutocompleteEditingValue? _placeholder; // remove
const BuildContext? _ctx = null; // replaced by pumped context in real test
```

> **Implementer:** factor the detection into pure top-level helpers so they're unit-testable without a `BuildContext`:
> - `({String input, List<VariableSuggestion> suggestions})? variablePromptsFor(LayeredVariableContext ctx, String line, int caret)` — runs `detectActiveVariableQuery` + `buildVariableSuggestions`.
> - `String variableInsertionWord(String name, {required bool hasClosingBraces})` — `hasClosingBraces ? name : '$name}}'`.
> `VariablePromptsBuilder.build` and the `CodePrompt` subclass are thin wrappers over these. Test the pure helpers (above) plus one pumped-widget test that the overlay appears (below).

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/variable_code_autocomplete_test.dart`
Expected: FAIL — file/helpers do not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/tabs/presentation/widgets/variable_code_autocomplete.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/core/utils/variable_autocomplete_query.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';
import 'package:re_editor/re_editor.dart';

/// Pure detection: the active `{{` query at [caret] in [line] and its ranked
/// suggestions, or null when the caret is not inside an open `{{name` token.
({String input, bool hasClosingBraces, List<VariableSuggestion> suggestions})?
variablePromptsFor(LayeredVariableContext ctx, String line, int caret) {
  final query = detectActiveVariableQuery(line, caret);
  if (query == null) return null;
  final suggestions = buildVariableSuggestions(
    query: query.query,
    userVariableNames: ctx.allVariables.keys,
    classify: ctx.classify,
  );
  if (suggestions.isEmpty) return null;
  return (
    input: query.query,
    hasClosingBraces: query.hasClosingBraces,
    suggestions: suggestions,
  );
}

String variableInsertionWord(String name, {required bool hasClosingBraces}) =>
    hasClosingBraces ? name : '$name}}';

/// A single variable suggestion as a re_editor [CodePrompt]. Carries the
/// resolved closing-brace decision so `.autocomplete` inserts `name` or
/// `name}}` correctly.
class _VariableCodePrompt extends CodePrompt {
  const _VariableCodePrompt({
    required super.word, // the variable name (display + match key)
    required this.hasClosingBraces,
    required this.classification,
  });

  final bool hasClosingBraces;
  final ResolvedVariable classification;

  @override
  bool match(String input) =>
      word.toLowerCase().contains(input.toLowerCase());

  @override
  CodeAutocompleteResult get autocomplete {
    final insert = variableInsertionWord(word, hasClosingBraces: hasClosingBraces);
    return CodeAutocompleteResult(
      input: '', // editing-value.input carries the typed query; see note
      word: insert,
      selection: TextSelection.collapsed(offset: insert.length),
    );
  }
}

/// re_editor prompts builder backed by the live [LayeredVariableContext].
class VariablePromptsBuilder implements CodeAutocompletePromptsBuilder {
  VariablePromptsBuilder(this.contextProvider);
  final LayeredVariableContext Function() contextProvider;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (!selection.isCollapsed) return null;
    final found = variablePromptsFor(
      contextProvider(),
      codeLine.text,
      selection.extentOffset,
    );
    if (found == null) return null;
    return CodeAutocompleteEditingValue(
      input: found.input,
      prompts: [
        for (final s in found.suggestions)
          _VariableCodePrompt(
            word: s.name,
            hasClosingBraces: found.hasClosingBraces,
            classification: s.classification,
          ),
      ],
      index: 0,
    );
  }
}

/// Themed suggestion list for the body editor — mirrors the rows used by the
/// TextField overlay (name + source + resolved preview).
PreferredSizeWidget Function(
  BuildContext,
  ValueNotifier<CodeAutocompleteEditingValue>,
  ValueChanged<CodeAutocompleteResult>,
)
get variableAutocompleteViewBuilder => _buildView;

PreferredSizeWidget _buildView(
  BuildContext context,
  ValueNotifier<CodeAutocompleteEditingValue> notifier,
  ValueChanged<CodeAutocompleteResult> onSelected,
) => _VariableCodeAutocompleteList(notifier: notifier, onSelected: onSelected);

const double _kRowHeight = 32;
const double _kMenuWidth = 280;
const double _kMaxMenuHeight = 240;

class _VariableCodeAutocompleteList extends StatelessWidget
    implements PreferredSizeWidget {
  const _VariableCodeAutocompleteList({
    required this.notifier,
    required this.onSelected,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize => Size(
    _kMenuWidth,
    math.min(_kRowHeight * notifier.value.prompts.length, _kMaxMenuHeight),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final palette = context.appPalette;
        final layout = context.appLayout;
        final theme = Theme.of(context);
        return Container(
          width: _kMenuWidth,
          constraints: const BoxConstraints(maxHeight: _kMaxMenuHeight),
          decoration: context.appDecoration.panelBox(context),
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: value.prompts.length,
            itemBuilder: (context, i) {
              final prompt = value.prompts[i] as _VariableCodePrompt;
              final c = prompt.classification;
              final isSecret = c.kind == VariableValueKind.secret;
              final isDynamic = c.kind == VariableValueKind.dynamicValue;
              final preview = isSecret ? '••••' : (c.value ?? '');
              final source = isDynamic ? 'dynamic' : (c.environmentName ?? '');
              final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
              return InkWell(
                onTap: () => onSelected(
                  value.copyWith(index: i).autocomplete,
                ),
                child: Container(
                  height: _kRowHeight,
                  color: i == value.index
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          prompt.word,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: layout.fontSizeNormal,
                            fontWeight: context.appTypography.titleWeight,
                            color: isDynamic
                                ? palette.variableResolved
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (source.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          source,
                          style: TextStyle(
                            fontSize: layout.fontSizeNormal,
                            color: muted,
                          ),
                        ),
                      ],
                      if (preview.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            preview,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: layout.fontSizeNormal,
                              color: muted,
                              fontStyle:
                                  isDynamic ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Wraps a body [child] (a `CodeEditor`) with variable autocomplete. Returns
/// [child] unchanged when there are no variables (no empty overlay).
Widget wrapBodyWithVariableAutocomplete({
  required LayeredVariableContext Function() contextProvider,
  required Widget child,
}) {
  return CodeAutocomplete(
    viewBuilder: variableAutocompleteViewBuilder,
    promptsBuilder: VariablePromptsBuilder(contextProvider),
    child: child,
  );
}
```

> **Note on `input`/`word`:** `CodeAutocompleteEditingValue.autocomplete` (lib) subtracts `editingValue.input.length` from the prompt result's selection offsets, and the editor deletes `[caret - input.length, caret]` before inserting `word`. Because we set `editingValue.input = query.query` and the prompt's `CodeAutocompleteResult.input = ''`, the net effect deletes exactly the typed query and inserts `word`, caret after it. Verify with the pumped test below; if the offset math needs a tweak, adjust the prompt's `selection` offset (this is the one place to validate against the running editor).

Then wire it in:
- In `request_editor_tabs.dart` `_RawBodyEditor`, wrap the `JsonCodeEditor` (the `CodeEditor`) with `wrapBodyWithVariableAutocomplete(contextProvider: ..., child: JsonCodeEditor(...))`. The Beautify button overlay in the `Stack` stays outside the wrap.
- The `contextProvider` must read the **current** `LayeredVariableContext`. Provide it from `request_view.dart`/`BodyTabView` by wrapping the body subtree in `TabVariableContextBuilder` and capturing the latest context into a closure (e.g. store it in a field updated each build, and pass `() => _latestBodyVarContext`). Keep it a closure (not a captured snapshot) so env switches mid-edit take effect on the next keystroke.

- [ ] **Step 4: Add a pumped-widget test that the overlay appears + inserts**

```dart
// In the same test file: pump a CodeEditor wrapped via
// wrapBodyWithVariableAutocomplete(contextProvider: () => ctx, child: CodeEditor(controller: c)),
// inside a MaterialApp with a brutalist theme and a real Overlay.
// 1. focus the editor; set controller text to '{{ho' with caret at offset 4.
//    (Use the controller API: c.text = '{{ho'; c.selection = CodeLineSelection.collapsed(index:0, offset:4);)
// 2. pumpAndSettle; expect(find.text('host'), findsOneWidget).
// 3. tap 'host'; pumpAndSettle; expect(c.text, '{{host}}').
```

> If driving the overlay purely via controller mutation doesn't trigger `show()` (it keys off keystroke-driven value changes), use `tester.enterText`-style input or send a key via `tester.sendKeyEvent` after positioning the caret. The pure-helper tests in Step 1 are the primary guarantee; this widget test is the integration check.

- [ ] **Step 5: Run tests**

Run: `fvm flutter test test/features/tabs/presentation/widgets/variable_code_autocomplete_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + format + commit**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart format lib test
git add lib/features/tabs/presentation/widgets/variable_code_autocomplete.dart lib/features/tabs/presentation/widgets/request_editor_tabs.dart lib/features/tabs/presentation/widgets/request_view.dart test/features/tabs/presentation/widgets/variable_code_autocomplete_test.dart
git commit -m "feat(variables): {{var}} autocomplete in the request body editor"
```

---

## Task 8: Body editor — `{{var}}` highlighting (flat-run merge)

Color `{{var}}` tokens on top of JSON highlighting in the body editor by extending the span builder. The active variable map decides resolved (`variableResolved`) vs unresolved (`variableUnresolved`).

**Files:**
- Create: `lib/features/tabs/presentation/widgets/variable_json_span_builder.dart`
- Modify: `lib/features/tabs/presentation/widgets/json_code_editor.dart` (use the new builder; pass a variables source)
- Modify: `request_editor_tabs.dart`/`request_view.dart` to feed the body controller the current variable map
- Test: `test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart`

**Interfaces:**
- Consumes: existing `jsonHighlightSpanBuilder` (`json_code_editor.dart`), `EnvironmentResolver.findVariables` + `isDynamic`, `LayeredVariableContext`.
- Produces:
  - `TextSpan variableAwareJsonSpan({required BuildContext context, required int index, required CodeLine codeLine, required TextSpan textSpan, required TextStyle style, required Map<String,String> variables, required Color resolvedColor, required Color unresolvedColor})` — JSON-highlights the line, then recolors `{{var}}` ranges.
  - `CodeLineEditingController createJsonCodeController({Map<String,String> Function()? variablesProvider, Color Function()? resolvedColor, Color Function()? unresolvedColor})` — extend the existing factory (keep the zero-arg call sites working via defaults).

**Approach (flat-run merge):** Produce a flat list of styled runs for the line by walking the JSON-highlighted `TextSpan` into `(start, end, style)` segments, then overlay each `{{var}}` character range with the variable color (variable wins). Emit a flat `TextSpan(children: [...])`. This avoids editing a nested span tree.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/variable_json_span_builder.dart';

void main() {
  testWidgets('colors a {{var}} token inside a JSON string', (tester) async {
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = variableAwareJsonSpan(
              context: context,
              index: 0,
              codeLine: const CodeLine('{"url": "{{host}}/v1"}'),
              textSpan: const TextSpan(text: '{"url": "{{host}}/v1"}'),
              style: const TextStyle(color: Colors.black),
              variables: const {'host': 'example.com'},
              resolvedColor: const Color(0xFF00FF00),
              unresolvedColor: const Color(0xFFFF0000),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    // Flatten the span text and assert a child run carrying '{{host}}' uses the
    // resolved color.
    final resolvedRun = _findRun(span, '{{host}}');
    expect(resolvedRun?.style?.color, const Color(0xFF00FF00));
  });

  testWidgets('a JSON line with no variables is unchanged vs base highlighter', (
    tester,
  ) async {
    // Assert variableAwareJsonSpan with empty variables produces the same
    // visible text as jsonHighlightSpanBuilder (no regression to JSON coloring).
  });

  testWidgets('unknown variable uses the unresolved color', (tester) async {
    // {{nope}} with variables {} -> run colored unresolvedColor.
  });
}

// Helper: depth-first search the span tree for the child whose text == needle.
TextSpan? _findRun(InlineSpan span, String needle) {
  // implement: walk span.children; return the TextSpan with .text == needle.
  return null; // implementer fills in
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart`
Expected: FAIL — file/function do not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/tabs/presentation/widgets/variable_json_span_builder.dart
import 'package:flutter/material.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart'
    show jsonHighlightSpanBuilder;
import 'package:re_editor/re_editor.dart';

/// JSON-highlights [codeLine], then recolors every `{{var}}` token: resolved
/// (in [variables] or a dynamic built-in) -> [resolvedColor], else
/// [unresolvedColor]. Variable color wins inside `{{…}}`. Implemented as a flat
/// run merge so it never mutates a nested span tree.
TextSpan variableAwareJsonSpan({
  required BuildContext context,
  required int index,
  required CodeLine codeLine,
  required TextSpan textSpan,
  required TextStyle style,
  required Map<String, String> variables,
  required Color resolvedColor,
  required Color unresolvedColor,
}) {
  final base = jsonHighlightSpanBuilder(
    context: context,
    index: index,
    codeLine: codeLine,
    textSpan: textSpan,
    style: style,
  );
  final text = codeLine.text;
  final matches = EnvironmentResolver.findVariables(text).toList();
  if (matches.isEmpty) return base;

  // 1. Flatten `base` into runs: List of (start, end, style).
  final runs = <({int start, int end, TextStyle style})>[];
  var cursor = 0;
  void visit(InlineSpan span, TextStyle inherited) {
    if (span is TextSpan) {
      final s = span.style == null ? inherited : inherited.merge(span.style);
      final t = span.text;
      if (t != null && t.isNotEmpty) {
        runs.add((start: cursor, end: cursor + t.length, style: s));
        cursor += t.length;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, s);
      }
    }
  }

  visit(base, style);
  if (cursor == 0) {
    // base had no leaf text (shouldn't happen) — fall back to whole-line style.
    runs.add((start: 0, end: text.length, style: style));
  }

  // 2. Build a per-character color override for variable ranges.
  Color? overrideAt(int i) {
    for (final m in matches) {
      if (i >= m.start && i < m.end) {
        final resolved =
            variables.containsKey(m.name) || EnvironmentResolver.isDynamic(m.name);
        return resolved ? resolvedColor : unresolvedColor;
      }
    }
    return null;
  }

  // 3. Re-emit runs, splitting where the variable override changes the color.
  final children = <InlineSpan>[];
  for (final run in runs) {
    var i = run.start;
    while (i < run.end) {
      final color = overrideAt(i);
      var j = i + 1;
      while (j < run.end && overrideAt(j) == color) {
        j++;
      }
      final segStyle = color == null
          ? run.style
          : run.style.copyWith(color: color, fontWeight: FontWeight.w800);
      children.add(TextSpan(text: text.substring(i, j), style: segStyle));
      i = j;
    }
  }
  return TextSpan(style: style, children: children);
}
```

Then:
- Extend `createJsonCodeController` in `json_code_editor.dart` to accept optional `variablesProvider`/`resolvedColor`/`unresolvedColor`; when provided, set the controller's `spanBuilder` to a closure calling `variableAwareJsonSpan(... variables: variablesProvider(), resolvedColor: resolvedColor(), ...)`. Keep the zero-arg form (no variable coloring) for non-body editors (response viewer).
- In `request_view.dart`, build the body controller with the providers reading the current `LayeredVariableContext.allVariables` and `context.appPalette.variableResolved/Unresolved` (read at span-build time, so theme/env changes apply). After an env change, call `_bodyController.notifyListeners()`/force a repaint isn't needed — re_editor rebuilds visible-line spans on text change; to refresh on env change without a text edit, the `TabVariableContextBuilder` rebuild can re-create or `markNeedsBuild` the editor. Acceptable simplification: variable recolor refreshes on the next keystroke/scroll. Document this.

> Avoid import cycles: `variable_json_span_builder.dart` imports `jsonHighlightSpanBuilder` from `json_code_editor.dart`; `json_code_editor.dart`'s extended factory imports `variable_json_span_builder.dart`. If that cycles, move `jsonHighlightSpanBuilder` into `variable_json_span_builder.dart` (or a shared `json_span.dart`) and have `json_code_editor.dart` import it. Resolve at implementation time; `fvm flutter analyze` will reveal a cycle.

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format + commit**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart format lib test
git add lib/features/tabs/presentation/widgets/variable_json_span_builder.dart lib/features/tabs/presentation/widgets/json_code_editor.dart lib/features/tabs/presentation/widgets/request_view.dart lib/features/tabs/presentation/widgets/request_editor_tabs.dart test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart
git commit -m "feat(variables): highlight {{var}} tokens in the body editor"
```

---

## Task 9: Body editor — hover preview ⚠️ (spike-gated)

Add the hover popover over the body editor's `{{var}}` tokens. **This is the flagged risk.** Spike feasibility first; if it requires forking `re_editor` internals, stop and deliver autocomplete + highlight only (Tasks 7–8), and record the deferral.

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/request_editor_tabs.dart` / `request_view.dart` (the body subtree)
- Possibly create: `lib/features/tabs/presentation/widgets/body_variable_hover.dart`
- Test: `test/features/tabs/presentation/widgets/body_variable_hover_test.dart` (only if feasible)

- [ ] **Step 1: Spike — can a pointer position map to a text offset?**

Investigate `re_editor 0.9.0` for a public API mapping a global/local pointer position to a `CodeLineSelection`/offset (the inverse of `calculateTextPositionScreenOffset`). Check `CodeLineEditingController`, the `CodeEditor` render object, and any exposed `selectionAt`/`positionAt`. Write a throwaway widget that, on `MouseRegion.onHover`, prints the mapped offset. Time-box to ~30 min.

Decision gate:
- **Feasible** (a usable position→offset exists, or token rects are derivable) → proceed to Step 2.
- **Not feasible without forking** → skip Steps 2-4. Update the spec + wiki note + PR description to state body hover is deferred (autocomplete + highlight shipped). Commit the docs change. Done with this task.

- [ ] **Step 2: Write the failing test (if feasible)**

```dart
// Pump the body editor with text '{{host}}' and variables {host: example.com}.
// Simulate a hover over the {{host}} token's screen rect.
// Expect a VariableHoverPopover (find by type) to appear showing 'example.com'.
```

- [ ] **Step 3: Implement (if feasible)**

Wrap the editor in a `MouseRegion`; on hover, map the pointer to a line+offset, find the `{{var}}` token (`EnvironmentResolver.findVariables` on that line) containing it, and drive a `VariableHoverController.showFor(context, ctx.classify(name), event.position)`. On exit / off-token, `scheduleHide()`.

- [ ] **Step 4: Run + analyze + format + commit (if feasible)**

```bash
fvm flutter test test/features/tabs/presentation/widgets/body_variable_hover_test.dart
fvm flutter analyze
fvm dart format lib test
git add -A
git commit -m "feat(variables): hover preview for {{var}} in the body editor"
```

---

## Task 10: Wiki sync + full done-bar

**Files:**
- The separate `Getman.wiki.git` repo (clone `https://github.com/thiagomiranda3/Getman.wiki.git`), the variables page.
- No app code (verification only).

- [ ] **Step 1: Run the full verification stack**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```
Expected: 0 issues from each analysis pass, format clean, all tests green. Fix anything that isn't.

- [ ] **Step 2: Update the wiki**

Clone the wiki repo, edit the variables page to state that `{{var}}` **autocomplete and highlighting** now apply to the **request body (raw/JSON), auth fields, and form-data values** — not just URL/params/headers — and that suggestions include **collection-scoped and dynamic** variables in every field. Add **hover preview** to the list of body capabilities **only if Task 9 shipped** (otherwise state hover applies to URL/params/headers/auth/form-data). Use verbatim UI labels. Commit + push to `master`.

```bash
# in the wiki clone
git add Variables.md _Sidebar.md
git commit -m "docs: variable autocomplete now covers body, auth & form-data"
git push origin master
```

- [ ] **Step 3: Final app-repo commit (if any verification fixes were made)**

```bash
git add -A
git commit -m "chore(variables): verification fixes for body/auth/form-data autocomplete"
```

---

## Self-Review

**Spec coverage:**
- Auth autocomplete+highlight+hover → Task 5 (atom from Task 3 bundles all three). ✓
- Form-data autocomplete+highlight+hover → Task 6. ✓
- Body autocomplete → Task 7. ✓
- Body highlighting → Task 8. ✓
- Body hover (risk + fallback) → Task 9, spike-gated, fallback documented. ✓
- Env + collection + dynamic everywhere; align params/headers → Tasks 1, 2, 4. ✓
- Shared `VariableTextField` atom + shared context builder → Tasks 2, 3. ✓
- Testing per field → each task's tests. ✓
- Wiki sync → Task 10. ✓
- No new blocs/events/persistence; presentation/util only → honored throughout. ✓

**Placeholder scan:** Test bodies for the bloc-harness-dependent widget tests (Tasks 2, 5, 6) intentionally reference "reuse the existing harness" because the exact fake/provider setup must match the current test tree, which the implementer reads at execution time — the assertions and arrange steps are concrete. The body-editor tests note one offset-math validation point (Task 7) flagged for live verification. No "TBD"/"add error handling"/"similar to Task N" placeholders.

**Type consistency:** `LayeredVariableContext` (Task 1) — `allVariables`, `allSecretKeys`, `classify`, `isEmpty`, `empty` — used consistently in Tasks 2-8. `VariableTextField(variables:, controller:, focusNode:, onChanged:, decoration:, obscureText:, fieldKey:)` consistent in Tasks 3, 5, 6. `variablePromptsFor` / `variableInsertionWord` / `VariablePromptsBuilder` / `wrapBodyWithVariableAutocomplete` consistent across Task 7 impl + tests. `variableAwareJsonSpan` signature consistent in Task 8 impl + test + the `createJsonCodeController` extension.

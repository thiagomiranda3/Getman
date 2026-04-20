# Getman — Project Documentation & Mandates

Getman is a high-performance, aesthetically pleasing HTTP client built with Flutter, featuring a Neo-Brutalist design. Tabbed request UI, collections tree with drag-and-drop, request history, local-only persistence.

---

## 1. Tech Stack

- **Flutter SDK**: pinned via `.fvmrc` — always invoke as `fvm flutter ...`, never plain `flutter`.
- **State**: `flutter_bloc` (strict UI/business-logic separation). All states and events are `Equatable`.
- **DI**: `get_it` (see `lib/core/di/injection_container.dart`). `GetIt` is referenced only from `main.dart` and DI setup — **never from widgets**.
- **Persistence**: `hive` + `hive_flutter` (local NoSQL).
- **Networking**: `dio` (cancel tokens wrapped by `NetworkCancelHandle`).
- **Routing**: `go_router` (single route today; room to grow in `AppRouter`).
- **Code editor**: `re_editor` + `re_highlight` (JSON highlighting, built-in find panel). Controller type is `CodeLineEditingController`, **not** `TextEditingController`.
- **UUIDs**: `uuid` package; entities generate their own IDs in constructors when not given.
- **Tree UI**: `flutter_fancy_tree_view` (**DISCONTINUED on pub.dev**; plan a migration to `two_dimensional_scrollables`).
- **Reactive helpers**: `collection` (for `MapEquality`, `ListEquality`, `firstWhereOrNull`).
- **Style**: `google_fonts` (Lexend base, JetBrainsMono in code editors).

---

## 2. Project Structure (Feature-First + Clean Architecture)

```
lib/
  core/
    di/              # GetIt bootstrap
    error/           # Failure / Exception hierarchy
    navigation/      # AppRouter, Intents (keyboard actions)
    network/         # NetworkService, HttpResponseEntity, HttpMethods, NetworkCancelHandle
    storage/         # HiveBoxes (box-name constants)
    theme/           # NeoBrutalistTheme, LayoutExtension, BrutalBounce
    ui/widgets/      # Cross-feature atoms: MethodBadge, Splitter
    utils/           # JsonUtils, CurlUtils, StatusColor
  features/
    <feature>/
      domain/        # Entities + abstract repositories + use cases (pure Dart, no Hive/Dio)
      data/          # Hive models (DTOs) + data sources + repository impls
      presentation/  # BLoC (event/state/bloc) + widgets + screens
  main.dart          # Bootstrap, global shortcuts, MultiBlocProvider, MaterialApp.router
```

Features today: `tabs`, `collections`, `history`, `settings`, `home`.

Mandatory rules:
- **Domain layer has zero imports from `data/` or Flutter UI.** Only pure Dart + `equatable`.
- **BLoCs depend on abstract `Repository` types**, never on `...Impl` or Hive/Dio directly.
- **Generic, reusable atoms** go in `lib/core/ui/widgets/`. Feature-specific widgets stay inside that feature.

---

## 3. Domain Model (Hive typeIds are load-bearing)

| typeId | Model | Box name | Notes |
|---|---|---|---|
| 0 | `SettingsModel` | `settings` | Single key `'current'`; loaded synchronously in `main()` |
| 1 | `HttpRequestConfig` | `history` | Shared between history and collection nodes |
| 2 | `HttpRequestTabModel` | `tabs` | Tab state including response cache |
| 3 | `CollectionNode` | `collections` | Nested (children list stored as `HiveField(3)`) |

**Never renumber an existing `typeId`.** Add new models with a fresh ID.

After editing any `@HiveType` field, regenerate:
```
dart run build_runner build --delete-conflicting-outputs
```

Entity ↔ Model boundary: every data-layer model implements `toEntity()` / `fromEntity()` / `copyWith()`. The domain entity is the public currency; Hive models never escape the `data/` layer.

---

## 4. Architecture Deep-Dive

### 4.1 Boot sequence (`main.dart` + `injection_container.dart`)
1. `WidgetsFlutterBinding.ensureInitialized()`.
2. `di.init()` — opens Hive, registers adapters, opens boxes, reads current settings synchronously, registers all use cases, repositories, data sources, BLoCs, `NetworkService`, `AppRouter`, `TabDirtyChecker`.
3. Returns `SettingsEntity` to pass as `initialSettings` into `SettingsBloc`.
4. `MultiRepositoryProvider` exposes cross-feature services (currently `TabDirtyChecker`) to the widget tree.
5. `MultiBlocProvider` creates `SettingsBloc`, `HistoryBloc`, `CollectionsBloc`, `TabsBloc` — each dispatches its `Load*` event eagerly at construction.
6. `Shortcuts` + `Actions` wire global keyboard intents: **Ctrl/Cmd+N** new tab, **+W** close tab, **+S** save, **+Enter** send, **+B** beautify JSON.

### 4.2 Tabs feature (most complex)
- `TabsBloc` owns a private `_RequestManager` mapping `tabId → NetworkCancelHandle`.
- **Debounced save**: any mutating event calls `_scheduleSave()` with a 10-second timer; `close()` cancels the timer, cancels in-flight requests, flushes a final `_persist()`.
- On `LoadTabs`, the BLoC sanitizes persisted tabs by resetting `isSending=false` — no real network call is alive after a restart.
- `_onRemoveTab` cancels the tab's handle before dropping the tab.
- `SendRequestUseCase` couples the network call with history persistence; history writes are best-effort (swallowed).
- Cancellation flow: UI dispatches `CancelRequest(index)` → `_RequestManager.cancel()` → Dio throws `DioExceptionType.cancel` → mapped to `NetworkFailure(type: cancelled)` → BLoC clears `isSending` without emitting response data.

### 4.3 Collections feature
- Tree is an immutable forest of `CollectionNodeEntity`. All mutations go through **pure** `CollectionsTreeHelper` functions (`addToParent`, `removeFromTree`, `renameInTree`, `toggleFavoriteInTree`, `updateConfigInTree`, `sort`, `findNode`). These never mutate input.
- Parent-lookup pattern: before calling `addToParent`, BLoC verifies the parent exists via `findNode`. If not found, node is appended to root (this is the correct behavior — `addToParent` does not signal missing parents).
- Sort order: favorites first, then folders, then leaves, each group alphabetical.
- Drag-and-drop: implemented with `Draggable<String>` (carrying `node.id`) and `DragTarget<String>`. Drop on root goes via the outer `DragTarget` at the list level.

### 4.4 History feature
- `HistoryBloc` subscribes to `watchHistory()` on construction; the data source uses `Hive.Box.watch()` and emits on every box change.
- **Dedup** in `HistoryLocalDataSourceImpl.addToHistory` is by `method + url + body` only. Headers differences do not dedupe.
- **Trim** uses a `while` loop so lowering `historyLimit` actually shrinks the box.
- Ordering: the data source returns `box.values` in insertion order; the repository reverses so UI gets newest-first.

### 4.5 Settings feature
- Settings are loaded synchronously at boot (`settingsBox.get('current')`) and injected as `initialSettings`. There is **no `LoadSettings` event** — do not add one unless you also change boot.
- Every `Update*` event both saves and emits in the handler — collections and settings persist immediately.

### 4.6 Dirty tracking
- `TabDirtyChecker` is registered as a lazy singleton and exposed to widgets via `RepositoryProvider`. Widgets read it with `context.read<TabDirtyChecker>()`.
- Logic: if the tab is linked to a collection node, compare `tab.config` with the saved node's config. Otherwise compare with the default `HttpRequestConfigEntity(id: tab.config.id)`.

### 4.7 Error model
- `core/error/exceptions.dart` — `PersistenceException` is thrown by data sources.
- `core/error/failures.dart` — `Failure` (Equatable, `implements Exception`) with `PersistenceFailure` and `NetworkFailure` (typed enum + statusCode). Repositories translate exceptions to failures at the `data/repositories/` boundary; BLoCs only ever handle `Failure` subtypes.

### 4.8 UI / Theming
- `NeoBrutalistTheme.theme(Brightness, isCompact)` builds a `ThemeData` including a `LayoutExtension` for sizing.
- **Never hardcode sizes or colors** — pull from `Theme.of(context).extension<LayoutExtension>()!` for sizing, from `theme.colorScheme`/`theme.dividerColor` for colors. Exceptions: method-specific colors via `NeoBrutalistTheme.getMethodColor()`, status-code colors via `StatusColor.forCode()` / `.forCodeAccent()`.
- HTTP method list: `HttpMethods.all` in `core/network/http_methods.dart` — don't hardcode `['GET','POST',…]`.
- `BrutalBounce` wraps tappable items to add the tap-scale bounce; use it for every button/icon-button that triggers an action.
- `NeoBrutalistTheme.brutalBox(context, offset: N)` returns the shadowed border decoration.
- Split panes: local `_localSplitRatio` / `_localSideMenuWidth` during drag, committed to BLoC in `onEnd`, then **reset to `null`** so the BLoC's value drives the widget again. If you add a new splitter, follow this pattern exactly.

### 4.9 Persistence summary

| Feature | When it writes |
|---|---|
| Settings | immediately on every `Update*` |
| Collections | immediately after every mutation (saves the whole tree) |
| History | via Hive `Box.watch()`; writes on each `add/delete/clear` |
| Tabs | debounced 10 s after any change + flush on `close()` |

---

## 5. Build & Test Commands

```
fvm flutter analyze                                           # must be 0 issues before claiming done
fvm flutter test                                              # all tests must be green
dart run build_runner build --delete-conflicting-outputs      # after any @HiveType change
fvm flutter run -d macos                                      # desktop run; supported targets in pubspec
```

Verification bar: **`fvm flutter analyze` produces `No issues found!` AND `fvm flutter test` is 100% green** before reporting work done.

---

## 6. Gotchas & Conventions (read before editing)

- **`HttpRequestConfig.==` / `hashCode` deliberately exclude `id`** so history dedup works on request signature. Do not "fix" this without a discussion.
- `HiveObject` subclasses sometimes override `==` — Hive uses its own keys internally, so this is safe, but changes flow through every consumer (collections reference `HttpRequestConfig` too).
- **BLoC tab lookups**: always `state.tabs.firstWhereOrNull((t) => t.tabId == id)`. Never index by position across state emissions — positions can shift.
- **`listenWhen` / `buildWhen` are not optional**: `RequestView` rebuilds are expensive; narrow selectors are how we keep the editor responsive.
- **Text controllers vs editor controllers**: `_KeyValueEditor` uses `TextEditingController`; the body and response panels use `re_editor.CodeLineEditingController`. Don't mix.
- **`_setControllerPreservingEnd`** (in `request_view.dart`) is the only safe way to push text into a `TextEditingController` without jumping the cursor during an echo-write.
- **`_lastEmitted` in `_KeyValueEditor`** intentionally suppresses rebuilds on echoes from the BLoC — keeps focus and half-typed state alive. Follow this pattern if you add similar inline editors.
- **Keyboard shortcuts** are declared in `main.dart` (global) and in `RequestView` / `MainScreen` (scoped `Actions`). The `NewTabIntent` Action is at the root; `CloseTabIntent` and `SendRequestIntent` at `MainScreen`; `SaveRequestIntent` and `BeautifyJsonIntent` inside `RequestView`. Put intents where `context.read<TabsBloc>()` is reachable.
- **Debug logs use `debugPrint`** — `print` is disallowed by the default lint profile.
- **`flutter_fancy_tree_view` is discontinued** — keep code changes compatible with eventual migration to `two_dimensional_scrollables`.
- Settings `splitRatio` is clamped to `[_splitMin, _splitMax]` (0.1..0.9) in `request_view.dart`. The `flex:` math uses `_splitFlexUnits=1000` — if you touch this, preserve the clamping so panes can't go to zero.

---

## 7. Development Mandates

### Architectural
- **Domain first**: new features start with entity + abstract repository + use case. No `data/`, no widgets yet.
- **Dependency inversion**: BLoCs depend on abstract types only.
- **Immutability**: `Equatable` on every state/event; `copyWith` on every entity.
- **GetIt stays in DI**: widgets reach services via `BlocProvider`, `RepositoryProvider`, or constructor injection. Never `sl<T>()` from a widget.

### UI / Styling
- **Theme adherence**: `LayoutExtension` for sizing, `brutalBox` / `BrutalBounce` for Neo-Brutalist components. No hardcoded colors or paddings.
- **Atomic design**: reusable widgets → `lib/core/ui/widgets/`.

### Workflow
- **Verify before claiming done**: `fvm flutter analyze` clean + `fvm flutter test` green.
- **Hive regen is not optional**: after any `@HiveField` or `@HiveType` change, rerun `build_runner`.
- **Surgical edits**: don't restructure unrelated code. One concern per change.

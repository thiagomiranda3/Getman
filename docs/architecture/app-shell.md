# App shell — boot, DI, providers, shortcuts, error model

> Deep-dive for the app shell (boot sequence, dependency injection, provider wiring, global keyboard shortcuts, and the error model). Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md.

## Boot sequence (`main.dart` + `injection_container.dart`)

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. `di.init()` — opens Hive, registers adapters, opens **all** boxes in parallel (`Future.wait`), reads current settings synchronously, registers all use cases, repositories, data sources, BLoCs, `NetworkService`, `AppRouter`, `TabDirtyChecker`. The `cookies` + `requestRules` boxes are opened on this cold-start path and the cookie jar is hydrated via `openAndHydrateDeferredBoxes` **before** `NetworkService` is usable — an earlier post-frame `warmUpDeferredBoxes` raced early sends (dropped cookies / skipped rules), so don't re-defer these without a readiness gate.
3. Returns `SettingsEntity` to pass as `initialSettings` into `SettingsBloc`.
4. `MultiRepositoryProvider` exposes cross-feature services to the widget tree: `TabDirtyChecker`, `NetworkService`, `CookieStore`, `WorkspaceSyncService`, and `UrlFocusRegistry` (the last lets the Cmd/Ctrl+L action focus the active tab's URL field — each `UrlBar` registers its `FocusNode` keyed by tab id).
5. `MultiBlocProvider` creates `SettingsBloc`, `HistoryBloc`, `CollectionsBloc`, `TabsBloc`, `EnvironmentsBloc` (plus the git blocs and `McpBloc`). Collections/Tabs/Environments dispatch their `Load*` event eagerly; `HistoryBloc` has no load event — it starts with `isLoading: true` and populates from its `watchHistory()` subscription (the stream yields the current list on subscribe). The root `BlocBuilder<SettingsBloc>` has a `buildWhen` gated to `themeId`/`isDarkMode`/`isCompactMode` — anything else would rebuild the whole `MaterialApp` per settings keystroke.

## Dependency injection

`get_it` (see `lib/core/di/injection_container.dart`) is the sole DI container. `GetIt` is referenced only from `main.dart` and DI setup — **never from widgets**. Widgets reach services via `BlocProvider`, `RepositoryProvider`, or constructor injection; the `avoid_get_it_in_widgets` custom lint enforces this.

The hand-written `Hive.registerAdapter(...)` calls also live in `injection_container.dart`. The generator auto-emits an unused `lib/hive_registrar.g.dart`; we keep the manual registration instead.

## Provider inventory

- **`MultiRepositoryProvider`** (cross-feature services): `TabDirtyChecker`, `NetworkService`, `CookieStore`, `WorkspaceSyncService`, `UrlFocusRegistry`.
- **`MultiBlocProvider`** (feature blocs): `SettingsBloc`, `HistoryBloc`, `CollectionsBloc`, `TabsBloc`, `EnvironmentsBloc`, the git blocs (`GitSyncBloc`, `ReviewBloc`, `PullRequestsBloc`, `ConflictBloc`), `RulesBloc`, `RealtimeBloc`, `McpBloc`.
- **`ChangeNotifierProvider`** above `MaterialApp`: `UpdateController` (drives the auto-update dialog).

## Global keyboard shortcuts

The global activator→intent map is `appShortcuts` in `main.dart` — a **computed** map (not a `const` literal; the digit→`JumpToTabIntent`/`JumpToPanelIntent` bindings are generated in a loop) built by `buildAppShortcuts({required bool useMeta})` and `@visibleForTesting`. The map is platform-exclusive: Meta on macOS, Control elsewhere (`Ctrl+Tab` / `Ctrl+Shift+Tab` stay cross-platform).

Bindings: **Ctrl/Cmd+N** new tab, **+W** close tab, **+S** save, **+Enter** send, **+B** beautify JSON, **+K** command palette, **+L** focus URL, **+E** switch environment, **Ctrl+Tab / Ctrl+Shift+Tab** next/prev tab, **Cmd/Ctrl+1–9** jump to tab, **+Shift+N** new panel, **+Shift+] / +Shift+[** next/prev panel, **+Shift+1–9** jump to panel.

### The root-`Actions` trap (the D8 fix)

Only the `Shortcuts` **map** lives at the root — `main.dart` has **no** root `Actions` widget at all. **Every** `Action` lives in `MainScreen` (or deeper). This is deliberate: a root `Actions` above `MaterialApp` would be reachable from focused widgets *inside every modal dialog* (dialogs push onto the same root Navigator), which is how Cmd/Ctrl+N used to stack invisible tabs behind the settings dialog / command palette. `MainScreen`'s `Actions` is a *sibling* of dialog routes, so its shortcuts are correctly dead while a dialog is up.

`Action`s are split by where their dependencies live:

- **`MainScreen`** hosts `NewTabIntent`, `CloseTabIntent`, `SendRequestIntent`, `NextTabIntent`/`PrevTabIntent`/`JumpToTabIntent`, the panel intents `NewPanelIntent`/`NextPanelIntent`/`PrevPanelIntent`/`JumpToPanelIntent`, `FocusUrlIntent`, **and the dialog-openers `CommandPaletteIntent` (+K) / `SwitchEnvironmentIntent` (+E)**. These need `activeIndex`/`tabs`/`UrlFocusRegistry`/env-resolution, or — for the dialog-openers — a context below `MaterialApp`+`Navigator` so `showDialog` finds `MaterialLocalizations`.
- **`RequestView`** hosts `SaveRequestIntent` and `BeautifyJsonIntent`.

Put intents where `context.read<TabsBloc>()` is reachable — and dialog-opening ones *below* `MaterialApp`.

### Editor shortcut pass-through

`re_editor` would otherwise **consume** two chords while a code editor holds focus. `AppCodeShortcutsActivatorsBuilder` (`json_code_editor.dart`, `@visibleForTesting`) strips them so the app's global shortcuts fire instead: it drops the `save` activator entirely (so **Cmd/Ctrl+S** → `SaveRequestIntent`) and removes the **Cmd/Ctrl+Enter** chord from `newLine` (so `SendRequestIntent` fires) while keeping plain / Shift / numpad Enter for real newlines.

## Error model (`core/error/`)

- `core/error/exceptions.dart` — `PersistenceException` is thrown by data sources.
- `core/error/failures.dart` — `Failure` (Equatable, `implements Exception`) with `PersistenceFailure` and `NetworkFailure` (typed enum + statusCode).
- Repositories translate exceptions to failures at the `data/repositories/` boundary; BLoCs only ever handle `Failure` subtypes.

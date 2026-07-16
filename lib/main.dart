import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/navigation/app_router.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/motion/theme_switch_transition.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/utils/workspace/workspace_bookmark.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/widgets/branch_sync_listener.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_sync_listener.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/widgets/network_settings_listener.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // All Google Fonts variants the app uses are bundled in assets/google_fonts/.
  // Disallow runtime fetching so a missing variant fails loudly in debug
  // instead of silently downloading over HTTP (jank + offline breakage).
  GoogleFonts.config.allowRuntimeFetching = false;
  final initialSettings = await di.init();
  final settings = await _resumeWorkspaceAccess(initialSettings);
  runApp(MyApp(initialSettings: settings));
}

/// Re-acquires macOS security-scoped access to the workspace folder from the
/// persisted bookmark before the first mirror write — the open-panel grant does
/// not survive relaunch under the App Sandbox. If macOS reports the bookmark as
/// stale, the refreshed bookmark is persisted so it keeps resolving. No-op on
/// other platforms / when no bookmark is stored; returns the settings to boot
/// with (refreshed when the bookmark changed, otherwise unchanged).
Future<SettingsEntity> _resumeWorkspaceAccess(SettingsEntity settings) async {
  final bookmark = settings.workspaceBookmark;
  if (bookmark == null || !WorkspaceBookmarks.supported) return settings;
  final access = await WorkspaceBookmarks.resolveAndAccess(bookmark);
  // Null → access could not be re-acquired; the mirror quietly fails until the
  // user reconnects the folder (the settings tile surfaces a reconnect hint).
  if (access == null) return settings;
  // Reconcile to the path/bookmark the OS actually authorized. A security-scoped
  // bookmark tracks the folder, not the path string, so the resolved path can
  // differ from the stored one if the folder was moved/renamed between launches.
  // Mirror writes target settings.workspacePath, so it must follow the resolved
  // path or writes hit a location we no longer have a grant for. Compare on the
  // path, not the `stale` flag — a move often resolves with stale=false, and
  // stale can be set with the path unchanged (app re-sign / OS upgrade).
  if (access.path != settings.workspacePath || access.bookmark != bookmark) {
    final refreshed = settings.copyWith(
      workspacePath: access.path,
      workspaceBookmark: access.bookmark,
    );
    await di.sl<SaveSettingsUseCase>()(refreshed);
    return refreshed;
  }
  return settings;
}

/// Digit keys for Cmd/Ctrl+1..9 → jump-to-tab (index 0..8).
const List<LogicalKeyboardKey> _tabDigitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Whether the primary shortcut modifier is ⌘ (meta) — true only on macOS,
/// where every app uses Cmd; Ctrl is the primary modifier everywhere else.
/// (Web on a Mac reports `TargetPlatform.macOS`, so browser builds match too.)
bool get _useMetaPrimary => defaultTargetPlatform == TargetPlatform.macOS;

/// Builds the global keyboard-shortcut map for one platform convention.
///
/// [useMeta] picks the *primary* modifier: ⌘ on macOS, Ctrl on Windows/Linux.
/// Each shortcut is bound to that single modifier only — so on macOS Ctrl+S no
/// longer saves, and on Windows the ⌘/Windows key no longer triggers app
/// actions. The lone exception is the tab-switch pair (`Ctrl+Tab` /
/// `Ctrl+Shift+Tab`), which is Ctrl on every platform: ⌘+Tab is the macOS app
/// switcher, and Ctrl+Tab is the universal in-app tab-cycle convention.
///
/// Exposed for tests so both platform variants can be asserted without an
/// `debugDefaultTargetPlatformOverride` dance.
@visibleForTesting
Map<ShortcutActivator, Intent> buildAppShortcuts({required bool useMeta}) {
  SingleActivator primary(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(key, control: !useMeta, meta: useMeta, shift: shift);

  return {
    primary(LogicalKeyboardKey.keyN): const NewTabIntent(),
    primary(LogicalKeyboardKey.keyW): const CloseTabIntent(),
    primary(LogicalKeyboardKey.keyS): const SaveRequestIntent(),
    primary(LogicalKeyboardKey.enter): const SendRequestIntent(),
    primary(LogicalKeyboardKey.keyB): const BeautifyJsonIntent(),
    primary(LogicalKeyboardKey.keyK): const CommandPaletteIntent(),
    primary(LogicalKeyboardKey.keyE): const SwitchEnvironmentIntent(),
    primary(LogicalKeyboardKey.keyL): const FocusUrlIntent(),
    // Tab-switch stays Ctrl on every platform (⌘+Tab is the OS app switcher).
    const SingleActivator(LogicalKeyboardKey.tab, control: true):
        const NextTabIntent(),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
        const PrevTabIntent(),
    for (var i = 0; i < _tabDigitKeys.length; i++)
      primary(_tabDigitKeys[i]): JumpToTabIntent(i),
    primary(LogicalKeyboardKey.keyN, shift: true): const NewPanelIntent(),
    primary(LogicalKeyboardKey.bracketRight, shift: true):
        const NextPanelIntent(),
    primary(LogicalKeyboardKey.bracketLeft, shift: true):
        const PrevPanelIntent(),
    for (var i = 0; i < _tabDigitKeys.length; i++)
      primary(_tabDigitKeys[i], shift: true): JumpToPanelIntent(i),
  };
}

/// Global keyboard shortcuts for the running platform (⌘ on macOS, Ctrl
/// elsewhere). Built once at load from [buildAppShortcuts]. Actions are
/// resolved at the root (new tab / command palette) and in `MainScreen`
/// (tab/send/save/focus).
@visibleForTesting
final Map<ShortcutActivator, Intent> appShortcuts = buildAppShortcuts(
  useMeta: _useMetaPrimary,
);

class MyApp extends StatelessWidget {
  const MyApp({required this.initialSettings, super.key});

  // Part of the public constructor consumed by widget tests; the boot settings
  // are applied via SettingsBloc seeding in di.init(), so the field itself is
  // not read inside build().
  final SettingsEntity initialSettings;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TabDirtyChecker>.value(
          value: di.sl<TabDirtyChecker>(),
        ),
        RepositoryProvider<UrlFocusRegistry>.value(
          value: di.sl<UrlFocusRegistry>(),
        ),
        ChangeNotifierProvider<RequestSectionIndex>.value(
          value: di.sl<RequestSectionIndex>(),
        ),
        RepositoryProvider<NetworkService>.value(
          value: di.sl<NetworkService>(),
        ),
        RepositoryProvider<RealtimeService>.value(
          value: di.sl<RealtimeService>(),
        ),
        RepositoryProvider<CookieStore>.value(value: di.sl<CookieStore>()),
        RepositoryProvider<WorkspaceSyncService>.value(
          value: di.sl<WorkspaceSyncService>(),
        ),
        ChangeNotifierProvider<WorkspacePulseController>.value(
          value: di.sl<WorkspacePulseController>(),
        ),
        ChangeNotifierProvider<UpdateController>.value(
          value: di.sl<UpdateController>(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => di.sl<SettingsBloc>()),
          // HistoryBloc loads itself by subscribing to watchHistory().
          BlocProvider(create: (_) => di.sl<HistoryBloc>()),
          BlocProvider(
            create: (_) =>
                di.sl<CollectionsBloc>()..add(const LoadCollections()),
          ),
          BlocProvider(create: (_) => di.sl<TabsBloc>()..add(const LoadTabs())),
          BlocProvider(
            create: (_) =>
                di.sl<EnvironmentsBloc>()..add(const LoadEnvironments()),
          ),
          BlocProvider(create: (_) => di.sl<RulesBloc>()),
          BlocProvider(create: (_) => di.sl<RealtimeBloc>()),
          BlocProvider(create: (_) => di.sl<McpBloc>()),
          BlocProvider(create: (_) => di.sl<ReviewBloc>()),
          BlocProvider(create: (_) => di.sl<GitSyncBloc>()),
          BlocProvider(create: (_) => di.sl<PullRequestsBloc>()),
          BlocProvider(create: (_) => di.sl<ConflictBloc>()),
        ],
        child: NetworkSettingsListener(
          child: WorkspaceSyncListener(
            child: BranchSyncListener(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                // Rebuilding here re-runs the theme builder and rebuilds the
                // entire MaterialApp — gate it to the three settings that
                // actually feed it.
                buildWhen: (prev, next) =>
                    prev.settings.themeId != next.settings.themeId ||
                    prev.settings.isDarkMode != next.settings.isDarkMode ||
                    prev.settings.isCompactMode != next.settings.isCompactMode,
                builder: (context, state) {
                  final settings = state.settings;
                  // NewTabIntent (and every other tab-strip shortcut) is
                  // wired in MainScreen, not here — see the D8 note there.
                  // A root Actions above MaterialApp/the Navigator is
                  // reachable from focused widgets INSIDE every modal dialog
                  // (showDialog pushes onto the same root Navigator this
                  // Shortcuts wraps), so Cmd/Ctrl+N used to fire from inside
                  // e.g. the settings dialog or the command palette's search
                  // field, silently stacking new tabs behind the modal
                  // barrier. MainScreen's Actions sits BELOW the router (a
                  // sibling of the dialog's overlay route, not an ancestor of
                  // it), so shortcuts wired there are correctly unreachable
                  // from a dialog — exactly like CloseTabIntent etc. already
                  // were.
                  return Shortcuts(
                    shortcuts: appShortcuts,
                    child: MaterialApp.router(
                      title: 'GETMAN',
                      debugShowCheckedModeBanner: false,
                      // Lerping ThemeData triggers ~12 full-tree rebuilds per
                      // theme change. The app's widget tree is too heavy for
                      // that; a single instant rebuild is both faster and
                      // visually cleaner.
                      themeAnimationDuration: Duration.zero,
                      theme: resolveThemeData(
                        settings.themeId,
                        Brightness.light,
                        isCompact: settings.isCompactMode,
                      ),
                      darkTheme: resolveThemeData(
                        settings.themeId,
                        Brightness.dark,
                        isCompact: settings.isCompactMode,
                      ),
                      themeMode: settings.isDarkMode
                          ? ThemeMode.dark
                          : ThemeMode.light,
                      routerConfig: di.sl<AppRouter>().router,
                      builder: (context, child) {
                        return Focus(
                          autofocus: true,
                          child: ThemeSwitchTransition(
                            themeId: settings.themeId,
                            reduceEffects: false,
                            child: context.appDecoration.scaffoldBackground(
                              context,
                              child: child ?? const SizedBox.shrink(),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

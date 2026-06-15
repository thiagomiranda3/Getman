import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/navigation/app_router.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/utils/workspace/workspace_bookmark.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_sync_listener.dart';
import 'package:getman/features/command_palette/presentation/widgets/command_palette.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/widgets/network_settings_listener.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

/// Global keyboard shortcuts. Built once (not const) so the Cmd/Ctrl+1..9
/// jump-to-tab bindings can be generated in a loop. Actions are resolved at the
/// root (new tab / command palette) and in `MainScreen` (tab/send/save/focus).
@visibleForTesting
final Map<ShortcutActivator, Intent> appShortcuts = {
  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
      const NewTabIntent(),
  const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
      const NewTabIntent(),
  const SingleActivator(LogicalKeyboardKey.keyW, control: true):
      const CloseTabIntent(),
  const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
      const CloseTabIntent(),
  const SingleActivator(LogicalKeyboardKey.keyS, control: true):
      const SaveRequestIntent(),
  const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
      const SaveRequestIntent(),
  const SingleActivator(LogicalKeyboardKey.enter, control: true):
      const SendRequestIntent(),
  const SingleActivator(LogicalKeyboardKey.enter, meta: true):
      const SendRequestIntent(),
  const SingleActivator(LogicalKeyboardKey.keyB, control: true):
      const BeautifyJsonIntent(),
  const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
      const BeautifyJsonIntent(),
  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
      const CommandPaletteIntent(),
  const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
      const CommandPaletteIntent(),
  const SingleActivator(LogicalKeyboardKey.tab, control: true):
      const NextTabIntent(),
  const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
      const PrevTabIntent(),
  const SingleActivator(LogicalKeyboardKey.keyL, control: true):
      const FocusUrlIntent(),
  const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
      const FocusUrlIntent(),
  for (var i = 0; i < _tabDigitKeys.length; i++) ...{
    SingleActivator(_tabDigitKeys[i], meta: true): JumpToTabIntent(i),
    SingleActivator(_tabDigitKeys[i], control: true): JumpToTabIntent(i),
  },
};

class MyApp extends StatelessWidget {
  const MyApp({required this.initialSettings, super.key});

  // Part of the public constructor consumed by widget tests; the boot settings
  // are applied via SettingsBloc seeding in di.init(), so the field itself is
  // not read inside build().
  // ignore: unreachable_from_main
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
        RepositoryProvider<NetworkService>.value(
          value: di.sl<NetworkService>(),
        ),
        RepositoryProvider<CookieStore>.value(value: di.sl<CookieStore>()),
        RepositoryProvider<WorkspaceSyncService>.value(
          value: di.sl<WorkspaceSyncService>(),
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
        ],
        child: NetworkSettingsListener(
          child: WorkspaceSyncListener(
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
                return Shortcuts(
                  shortcuts: appShortcuts,
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      NewTabIntent: CallbackAction<NewTabIntent>(
                        onInvoke: (intent) =>
                            context.read<TabsBloc>().add(const AddTab()),
                      ),
                      CommandPaletteIntent:
                          CallbackAction<CommandPaletteIntent>(
                            onInvoke: (intent) {
                              unawaited(CommandPalette.show(context));
                              return null;
                            },
                          ),
                    },
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
                          child: context.appDecoration.scaffoldBackground(
                            context,
                            child: child ?? const SizedBox.shrink(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

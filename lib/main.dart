import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/navigation/app_router.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
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
  runApp(MyApp(initialSettings: initialSettings));
}

class MyApp extends StatelessWidget {
  final SettingsEntity initialSettings;
  const MyApp({super.key, required this.initialSettings});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TabDirtyChecker>.value(value: di.sl<TabDirtyChecker>()),
      ],
      child: MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<SettingsBloc>()),
        // HistoryBloc loads itself by subscribing to watchHistory().
        BlocProvider(create: (_) => di.sl<HistoryBloc>()),
        BlocProvider(create: (_) => di.sl<CollectionsBloc>()..add(const LoadCollections())),
        BlocProvider(create: (_) => di.sl<TabsBloc>()..add(const LoadTabs())),
        BlocProvider(create: (_) => di.sl<EnvironmentsBloc>()..add(const LoadEnvironments())),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        // Rebuilding here re-runs the theme builder and rebuilds the entire
        // MaterialApp — gate it to the three settings that actually feed it.
        buildWhen: (prev, next) =>
            prev.settings.themeId != next.settings.themeId ||
            prev.settings.isDarkMode != next.settings.isDarkMode ||
            prev.settings.isCompactMode != next.settings.isCompactMode,
        builder: (context, state) {
          final settings = state.settings;
          return Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyN, control: true): NewTabIntent(),
              SingleActivator(LogicalKeyboardKey.keyN, meta: true): NewTabIntent(),
              SingleActivator(LogicalKeyboardKey.keyW, control: true): CloseTabIntent(),
              SingleActivator(LogicalKeyboardKey.keyW, meta: true): CloseTabIntent(),
              SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveRequestIntent(),
              SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveRequestIntent(),
              SingleActivator(LogicalKeyboardKey.enter, control: true): SendRequestIntent(),
              SingleActivator(LogicalKeyboardKey.enter, meta: true): SendRequestIntent(),
              SingleActivator(LogicalKeyboardKey.keyB, control: true): BeautifyJsonIntent(),
              SingleActivator(LogicalKeyboardKey.keyB, meta: true): BeautifyJsonIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                NewTabIntent: CallbackAction<NewTabIntent>(
                  onInvoke: (intent) => context.read<TabsBloc>().add(const AddTab()),
                ),
              },
              child: MaterialApp.router(
                title: 'GETMAN',
                debugShowCheckedModeBanner: false,
                // Lerping ThemeData triggers ~12 full-tree rebuilds per theme
                // change. The app's widget tree is too heavy for that; a single
                // instant rebuild is both faster and visually cleaner.
                themeAnimationDuration: Duration.zero,
                theme: resolveThemeData(settings.themeId, Brightness.light, isCompact: settings.isCompactMode),
                darkTheme: resolveThemeData(settings.themeId, Brightness.dark, isCompact: settings.isCompactMode),
                themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injection_container.dart' as di;
import 'core/theme/theme_registry.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';
import 'features/settings/presentation/bloc/settings_state.dart';
import 'features/history/presentation/bloc/history_bloc.dart';
import 'features/history/presentation/bloc/history_event.dart';
import 'features/collections/presentation/bloc/collections_bloc.dart';
import 'features/collections/presentation/bloc/collections_event.dart';
import 'features/tabs/presentation/bloc/tabs_bloc.dart';
import 'features/tabs/presentation/bloc/tabs_event.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/navigation/intents.dart';
import 'features/settings/domain/entities/settings_entity.dart';
import 'features/home/domain/usecases/tab_dirty_checker.dart';
import 'core/navigation/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        BlocProvider(create: (_) => di.sl<HistoryBloc>()..add(const LoadHistory())),
        BlocProvider(create: (_) => di.sl<CollectionsBloc>()..add(const LoadCollections())),
        BlocProvider(create: (_) => di.sl<TabsBloc>()..add(const LoadTabs())),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
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
                theme: resolveTheme(settings.themeId)(Brightness.light, isCompact: settings.isCompactMode),
                darkTheme: resolveTheme(settings.themeId)(Brightness.dark, isCompact: settings.isCompactMode),
                themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
                routerConfig: di.sl<AppRouter>().router,
                builder: (context, child) {
                  return Focus(
                    autofocus: true,
                    child: child ?? const SizedBox.shrink(),
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


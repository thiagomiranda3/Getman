import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injection_container.dart' as di;
import 'core/theme/neo_brutalist_theme.dart';
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
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<SettingsBloc>()),
        BlocProvider(create: (_) => di.sl<HistoryBloc>()..add(LoadHistory())),
        BlocProvider(create: (_) => di.sl<CollectionsBloc>()..add(LoadCollections())),
        BlocProvider(create: (_) => di.sl<TabsBloc>()..add(LoadTabs())),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          final settings = state.settings;
          return Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.keyN, control: true): const NewTabIntent(),
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true): const NewTabIntent(),
              const SingleActivator(LogicalKeyboardKey.keyW, control: true): const CloseTabIntent(),
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true): const CloseTabIntent(),
              const SingleActivator(LogicalKeyboardKey.keyS, control: true): const SaveRequestIntent(),
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): const SaveRequestIntent(),
              const SingleActivator(LogicalKeyboardKey.enter, control: true): const SendRequestIntent(),
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): const SendRequestIntent(),
              const SingleActivator(LogicalKeyboardKey.keyB, control: true): const BeautifyJsonIntent(),
              const SingleActivator(LogicalKeyboardKey.keyB, meta: true): const BeautifyJsonIntent(),
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
                theme: NeoBrutalistTheme.theme(Brightness.light, isCompact: settings.isCompactMode),
                darkTheme: NeoBrutalistTheme.theme(Brightness.dark, isCompact: settings.isCompactMode),
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
    );
  }
}


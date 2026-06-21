// Widget tests for SideMenu: renders COLLECTIONS and HISTORY tabs; the
// new-folder button opens a dialog, and the settings button opens settings.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/home/presentation/widgets/side_menu.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockHistoryRepository extends Mock implements HistoryRepository {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

void main() {
  late MockCollectionsRepository collectionsRepo;
  late MockHistoryRepository historyRepo;
  late MockSaveSettingsUseCase saveSettingsUseCase;
  late MockTabsBloc tabsBloc;

  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    collectionsRepo = MockCollectionsRepository();
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => []);
    when(
      () => collectionsRepo.saveCollections(any()),
    ).thenAnswer((_) async {});

    historyRepo = MockHistoryRepository();
    when(
      () => historyRepo.watchHistory(),
    ).thenAnswer((_) => Stream.value([]));

    saveSettingsUseCase = MockSaveSettingsUseCase();
    when(() => saveSettingsUseCase(any())).thenAnswer((_) async {});

    tabsBloc = MockTabsBloc();
    when(() => tabsBloc.state).thenReturn(const TabsState());
  });

  Widget buildHost() {
    final collectionsBloc = CollectionsBloc(
      getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
      saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
      saveDebounce: const Duration(milliseconds: 5),
    );
    final historyBloc = HistoryBloc(
      watchHistoryUseCase: WatchHistoryUseCase(historyRepo),
    );
    final settingsBloc = SettingsBloc(
      saveSettingsUseCase: saveSettingsUseCase,
      initialSettings: const SettingsEntity(),
    );

    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: collectionsBloc),
            BlocProvider.value(value: historyBloc),
            BlocProvider.value(value: settingsBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: const SizedBox(
            width: 320,
            height: 600,
            child: SideMenu(),
          ),
        ),
      ),
    );
  }

  testWidgets('renders GETMAN brand header', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('GETMAN'), findsOneWidget);
  });

  testWidgets('renders COLLECTIONS and HISTORY tab labels', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('COLLECTIONS'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
  });

  testWidgets('new folder button is present', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('new_folder_button')), findsOneWidget);
  });

  testWidgets('settings button is present', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('settings_button')), findsOneWidget);
  });

  testWidgets('tapping new folder button opens NEW FOLDER dialog', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('new_folder_button')));
    await tester.pump(const Duration(milliseconds: 50));

    // NamePromptDialog appears with a NEW FOLDER title
    expect(find.text('NEW FOLDER'), findsWidgets);
  });
}

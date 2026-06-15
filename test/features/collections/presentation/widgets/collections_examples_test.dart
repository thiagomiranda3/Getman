// Widget test for the M10 saved-examples UI in the collections tree: a request
// with examples shows a count + expand chevron; expanding reveals the example
// rows; tapping one opens it as a tab with its captured response shown.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

void main() {
  late MockCollectionsRepository collectionsRepo;
  late MockTabsRepository tabsRepo;
  late MockSendRequestUseCase sendUseCase;

  setUpAll(() {
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
  });

  setUp(() {
    collectionsRepo = MockCollectionsRepository();
    tabsRepo = MockTabsRepository();
    sendUseCase = MockSendRequestUseCase();
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => const []);
    when(() => collectionsRepo.saveCollections(any())).thenAnswer((_) async {});
    when(() => tabsRepo.getTabs()).thenAnswer((_) async => const []);
    when(() => tabsRepo.saveTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putTab(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deleteTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.saveTabOrder(any())).thenAnswer((_) async {});
  });

  final example = SavedExampleEntity(
    id: 'e1',
    name: 'My Example',
    capturedAt: DateTime.utc(2026, 6, 14),
    config: const HttpRequestConfigEntity(
      id: 'R',
      url: 'https://api/users',
      statusCode: 200,
      responseBody: '{"ok":true}',
      durationMs: 7,
    ),
  );

  Future<({CollectionsBloc collections, TabsBloc tabs})> pump(
    WidgetTester tester,
  ) async {
    final collectionsBloc =
        CollectionsBloc(
          getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
          saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
          saveDebounce: const Duration(milliseconds: 5),
        )..add(
          ReplaceCollections([
            CollectionNodeEntity(
              id: 'R',
              name: 'GetUsers',
              isFolder: false,
              config: const HttpRequestConfigEntity(
                id: 'R',
                url: 'https://api/users',
              ),
              examples: [example],
            ),
          ]),
        );
    await collectionsBloc.stream.first;

    final tabsBloc = TabsBloc(
      repository: tabsRepo,
      sendRequestUseCase: sendUseCase,
    )..add(const LoadTabs());
    await tabsBloc.stream.firstWhere((s) => !s.isLoading);

    addTearDown(collectionsBloc.close);
    addTearDown(tabsBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: collectionsBloc),
              BlocProvider.value(value: tabsBloc),
            ],
            child: const CollectionsList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (collections: collectionsBloc, tabs: tabsBloc);
  }

  testWidgets('a request with examples is collapsed by default, then expands', (
    tester,
  ) async {
    await pump(tester);

    // The count badge shows; the example row is hidden until expanded.
    expect(find.text('GETUSERS'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('My Example'), findsNothing);

    // Tap the leaf's expand chevron.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    await tester.pumpAndSettle();

    expect(find.text('My Example'), findsOneWidget);
  });

  testWidgets('tapping an example opens it as a tab with its response', (
    tester,
  ) async {
    final blocs = await pump(tester);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Example'));
    await tester.pumpAndSettle();

    // The opened example is the tab carrying a response (a default empty tab
    // may also exist).
    final opened = blocs.tabs.state.tabs.firstWhere((t) => t.response != null);
    expect(opened.response!.statusCode, 200);
    expect(opened.response!.body, '{"ok":true}');
    expect(opened.collectionName, 'GetUsers · My Example');
    // Opened unlinked so re-sending never overwrites the saved request.
    expect(opened.collectionNodeId, isNull);
  });
}

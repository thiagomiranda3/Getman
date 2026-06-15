import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/home/presentation/widgets/tab_widget.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

HttpRequestTabEntity _linkedTab() => const HttpRequestTabEntity(
  tabId: 'tab1',
  config: HttpRequestConfigEntity(id: 'node1', url: 'https://api/users'),
  collectionName: 'GetUsers',
  collectionNodeId: 'node1',
);

HttpRequestTabEntity _emptyTab() => const HttpRequestTabEntity(
  tabId: 'tab2',
  config: HttpRequestConfigEntity(id: 'node2'),
);

void main() {
  late MockTabsRepository tabsRepo;
  late MockSendRequestUseCase sendUseCase;
  late MockCollectionsRepository collectionsRepo;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
  });

  setUp(() {
    tabsRepo = MockTabsRepository();
    sendUseCase = MockSendRequestUseCase();
    collectionsRepo = MockCollectionsRepository();
    when(() => tabsRepo.saveTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putTab(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deleteTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.saveTabOrder(any())).thenAnswer((_) async {});
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => const []);
    when(() => collectionsRepo.saveCollections(any())).thenAnswer((_) async {});
  });

  Future<void> pumpTab(WidgetTester tester, HttpRequestTabEntity tab) async {
    when(() => tabsRepo.getTabs()).thenAnswer((_) async => [tab]);
    final tabsBloc = TabsBloc(
      repository: tabsRepo,
      sendRequestUseCase: sendUseCase,
    )..add(const LoadTabs());
    await tabsBloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);

    final collectionsBloc = CollectionsBloc(
      getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
      saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
      saveDebounce: const Duration(milliseconds: 5),
    )..add(const ReplaceCollections([]));
    await collectionsBloc.stream.first;

    addTearDown(tabsBloc.close);
    addTearDown(collectionsBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: tabsBloc),
              BlocProvider.value(value: collectionsBloc),
            ],
            child: RepositoryProvider<TabDirtyChecker>.value(
              value: const TabDirtyChecker(),
              // Centered so the screen's top-left corner (Offset.zero) is
              // OUTSIDE the tab — lets the pointer move on/off it to fire
              // MouseRegion onEnter/onExit.
              child: Center(
                child: TabWidget(
                  tabId: tab.tabId,
                  index: 0,
                  isActive: true,
                  onTap: () {},
                  onClose: () async => true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The screen's top-left corner, outside the centered tab — moving on/off it
  // fires MouseRegion onEnter/onExit.
  const outside = Offset.zero;

  Future<TestGesture> hoverTab(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: outside);
    addTearDown(gesture.removePointer);
    await tester.pump();
    // The tab content is aligned to the top-left of its (tall) layout box, over
    // the title — not the geometric center. Aim just inside the top-left.
    final rect = tester.getRect(find.byType(TabWidget));
    await gesture.moveTo(rect.topLeft + const Offset(12, 12));
    await tester.pumpAndSettle();
    return gesture;
  }

  testWidgets('shows name + URL in a tooltip after the hover delay', (
    tester,
  ) async {
    await pumpTab(tester, _linkedTab());
    final tooltip = find.byKey(const ValueKey('tab_tooltip_tab1'));

    await hoverTab(tester);
    // Before the delay elapses, nothing is shown.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tooltip, findsNothing);

    // After the delay, the tooltip appears with both lines.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(tooltip, findsOneWidget);
    expect(
      find.descendant(of: tooltip, matching: find.text('GetUsers')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tooltip, matching: find.text('https://api/users')),
      findsOneWidget,
    );
  });

  testWidgets('omits the URL line when the tab has no URL', (tester) async {
    await pumpTab(tester, _emptyTab());
    final tooltip = find.byKey(const ValueKey('tab_tooltip_tab2'));

    await hoverTab(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(tooltip, findsOneWidget);
    expect(
      find.descendant(of: tooltip, matching: find.text('NEW REQUEST')),
      findsOneWidget,
    );
    // Only the name line — no muted URL row.
    expect(
      find.descendant(of: tooltip, matching: find.byType(Text)),
      findsOneWidget,
    );
  });

  testWidgets('does not show the tooltip if the pointer leaves before delay', (
    tester,
  ) async {
    await pumpTab(tester, _linkedTab());
    final tooltip = find.byKey(const ValueKey('tab_tooltip_tab1'));

    final gesture = await hoverTab(tester);
    await tester.pump(const Duration(milliseconds: 200)); // < 500ms delay
    await gesture.moveTo(outside); // leave the tab
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tooltip, findsNothing);
  });
}

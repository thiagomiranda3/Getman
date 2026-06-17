// Widget tests for closePanelWithSavePrompt:
//   (a) no dirty tabs → confirm → RemovePanel dispatched
//   (b) dirty + "DISCARD ALL & CLOSE" → RemovePanel, no CollectionsBloc add
//   (c) dirty + "REVIEW & SAVE…" → save path → RemovePanel
//   (d) dirty + "REVIEW & SAVE…" → "CANCEL REVIEW" → no RemovePanel

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/panel_close_coordinator.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks / fakes
// ---------------------------------------------------------------------------

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const String _panelId = 'p1';
const String _panel2Id = 'p2';

HttpRequestTabEntity _tab(String id, {String? nodeId, String? name}) =>
    HttpRequestTabEntity(
      tabId: id,
      collectionNodeId: nodeId,
      collectionName: name,
      config: HttpRequestConfigEntity(id: id),
    );

/// A [TabDirtyChecker] that delegates to a callback so each test controls the
/// dirty verdict per tab.
class _FakeDirtyChecker implements TabDirtyChecker {
  _FakeDirtyChecker({required this.isDirty});
  final bool Function(HttpRequestTabEntity) isDirty;

  @override
  bool call({
    required HttpRequestTabEntity tab,
    required Map<String, HttpRequestConfigEntity> savedConfigs,
  }) => isDirty(tab);
}

PanelEntity _panel(String id, List<HttpRequestTabEntity> tabs) => PanelEntity(
  id: id,
  name: 'Panel $id',
  tabs: tabs,
  activeTabId: tabs.first.tabId,
);

TabsState _state({
  required List<PanelEntity> panels,
  String activePanelId = _panelId,
}) => TabsState(
  panels: panels,
  activePanelId: activePanelId,
  tabs: panels.firstWhere((p) => p.id == activePanelId).tabs,
);

Widget _host(
  WidgetTester tester, {
  required MockTabsBloc tabsBloc,
  required MockCollectionsBloc collectionsBloc,
  required TabDirtyChecker dirtyChecker,
  required String panelId,
}) {
  return MaterialApp(
    theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
          RepositoryProvider<TabDirtyChecker>.value(value: dirtyChecker),
        ],
        child: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey('close_panel_trigger'),
              onPressed: () => closePanelWithSavePrompt(context, panelId),
              child: const Text('Close Panel'),
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
    registerFallbackValue(_FakeCollectionsEvent());
  });

  late MockTabsBloc tabsBloc;
  late MockCollectionsBloc collectionsBloc;

  setUp(() {
    tabsBloc = MockTabsBloc();
    collectionsBloc = MockCollectionsBloc();

    when(() => tabsBloc.add(any())).thenReturn(null);
    when(() => collectionsBloc.add(any())).thenReturn(null);

    // CollectionsState with no nodes → configById is empty.
    when(() => collectionsBloc.state).thenReturn(CollectionsState());
  });

  // (a) no dirty tabs --------------------------------------------------------
  testWidgets('no dirty tabs: confirm dialog → RemovePanel dispatched', (
    tester,
  ) async {
    final tab1 = _tab('t1');
    final p1 = _panel(_panelId, [tab1]);
    final p2 = _panel(_panel2Id, [_tab('t2')]);

    when(() => tabsBloc.state).thenReturn(
      _state(panels: [p1, p2]),
    );

    final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => false);

    await tester.pumpWidget(
      _host(
        tester,
        tabsBloc: tabsBloc,
        collectionsBloc: collectionsBloc,
        dirtyChecker: dirtyChecker,
        panelId: _panelId,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
    await tester.pumpAndSettle();

    // ConfirmDialog is shown with CLOSE label.
    expect(find.text('CLOSE PANEL?'), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    verify(() => tabsBloc.add(const RemovePanel(_panelId))).called(1);
    verifyNever(() => collectionsBloc.add(any()));
  });

  // (a) cancel on confirm dialog → no RemovePanel ---------------------------
  testWidgets('no dirty tabs: CANCEL on confirm → no RemovePanel', (
    tester,
  ) async {
    final p1 = _panel(_panelId, [_tab('t1')]);
    final p2 = _panel(_panel2Id, [_tab('t2')]);

    when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

    final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => false);

    await tester.pumpWidget(
      _host(
        tester,
        tabsBloc: tabsBloc,
        collectionsBloc: collectionsBloc,
        dirtyChecker: dirtyChecker,
        panelId: _panelId,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    verifyNever(() => tabsBloc.add(const RemovePanel(_panelId)));
  });

  // (b) dirty + DISCARD ALL & CLOSE ------------------------------------------
  testWidgets(
    'dirty tabs: DISCARD ALL & CLOSE → RemovePanel, no save dispatched',
    (tester) async {
      final tab1 = _tab('t1');
      final p1 = _panel(_panelId, [tab1]);
      final p2 = _panel(_panel2Id, [_tab('t2')]);

      when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

      final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => true);

      await tester.pumpWidget(
        _host(
          tester,
          tabsBloc: tabsBloc,
          collectionsBloc: collectionsBloc,
          dirtyChecker: dirtyChecker,
          panelId: _panelId,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
      await tester.pumpAndSettle();

      // Summary dialog appears.
      expect(find.text('DISCARD ALL & CLOSE'), findsOneWidget);
      expect(find.text('REVIEW & SAVE…'), findsOneWidget);

      await tester.tap(find.text('DISCARD ALL & CLOSE'));
      await tester.pumpAndSettle();

      verify(() => tabsBloc.add(const RemovePanel(_panelId))).called(1);
      verifyNever(() => collectionsBloc.add(any()));
    },
  );

  // (d) dirty + CANCEL from summary dialog → no RemovePanel -----------------
  testWidgets('dirty tabs: CANCEL on summary → no RemovePanel', (
    tester,
  ) async {
    final p1 = _panel(_panelId, [_tab('t1')]);
    final p2 = _panel(_panel2Id, [_tab('t2')]);

    when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

    final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => true);

    await tester.pumpWidget(
      _host(
        tester,
        tabsBloc: tabsBloc,
        collectionsBloc: collectionsBloc,
        dirtyChecker: dirtyChecker,
        panelId: _panelId,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    verifyNever(() => tabsBloc.add(const RemovePanel(_panelId)));
    verifyNever(() => collectionsBloc.add(any()));
  });

  // (c) dirty + REVIEW & SAVE → SAVE (linked) → RemovePanel ----------------
  testWidgets(
    'dirty + REVIEW & SAVE: save linked tab → RemovePanel after review',
    (tester) async {
      const nodeId = 'node-1';
      final tab1 = _tab('t1', nodeId: nodeId, name: 'My Request');

      // Add the node to CollectionsBloc state so findNode returns it.
      const savedNode = CollectionNodeEntity(
        id: nodeId,
        name: 'My Request',
        config: HttpRequestConfigEntity(id: 'cfg-orig'),
      );
      final colState = CollectionsState(collections: const [savedNode]);
      when(() => collectionsBloc.state).thenReturn(colState);

      final p1 = _panel(_panelId, [tab1]);
      final p2 = _panel(_panel2Id, [_tab('t2')]);
      when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

      final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => true);

      await tester.pumpWidget(
        _host(
          tester,
          tabsBloc: tabsBloc,
          collectionsBloc: collectionsBloc,
          dirtyChecker: dirtyChecker,
          panelId: _panelId,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
      await tester.pumpAndSettle();

      // Summary dialog
      await tester.tap(find.text('REVIEW & SAVE…'));
      await tester.pumpAndSettle();

      // Per-tab dialog: title contains the tab's displayTitle
      expect(find.textContaining('My Request'), findsAtLeastNWidgets(1));
      expect(find.text('SAVE'), findsOneWidget);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      // UpdateNodeRequest dispatched
      verify(
        () => collectionsBloc.add(
          any(that: isA<UpdateNodeRequest>()),
        ),
      ).called(1);

      // Panel closed
      verify(() => tabsBloc.add(const RemovePanel(_panelId))).called(1);
    },
  );

  // (c) dirty + REVIEW & SAVE → DISCARD → RemovePanel ----------------------
  testWidgets(
    'dirty + REVIEW & SAVE: discard single dirty tab → RemovePanel',
    (tester) async {
      final tab1 = _tab('t1');
      final p1 = _panel(_panelId, [tab1]);
      final p2 = _panel(_panel2Id, [_tab('t2')]);
      when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

      final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => true);

      await tester.pumpWidget(
        _host(
          tester,
          tabsBloc: tabsBloc,
          collectionsBloc: collectionsBloc,
          dirtyChecker: dirtyChecker,
          panelId: _panelId,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('REVIEW & SAVE…'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DISCARD'));
      await tester.pumpAndSettle();

      verifyNever(() => collectionsBloc.add(any()));
      verify(() => tabsBloc.add(const RemovePanel(_panelId))).called(1);
    },
  );

  // (d) dirty + REVIEW & SAVE → CANCEL REVIEW → no RemovePanel -------------
  testWidgets(
    'dirty + REVIEW & SAVE: CANCEL REVIEW → panel not removed',
    (tester) async {
      final tab1 = _tab('t1');
      final p1 = _panel(_panelId, [tab1]);
      final p2 = _panel(_panel2Id, [_tab('t2')]);
      when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

      final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => true);

      await tester.pumpWidget(
        _host(
          tester,
          tabsBloc: tabsBloc,
          collectionsBloc: collectionsBloc,
          dirtyChecker: dirtyChecker,
          panelId: _panelId,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('REVIEW & SAVE…'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CANCEL REVIEW'));
      await tester.pumpAndSettle();

      verifyNever(() => tabsBloc.add(const RemovePanel(_panelId)));
      verifyNever(() => collectionsBloc.add(any()));
    },
  );

  // bail: only one panel → no dialog shown ----------------------------------
  testWidgets('only one panel: bails silently without any dialog', (
    tester,
  ) async {
    final p1 = _panel(_panelId, [_tab('t1')]);
    when(() => tabsBloc.state).thenReturn(_state(panels: [p1]));

    final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => false);

    await tester.pumpWidget(
      _host(
        tester,
        tabsBloc: tabsBloc,
        collectionsBloc: collectionsBloc,
        dirtyChecker: dirtyChecker,
        panelId: _panelId,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
    await tester.pumpAndSettle();

    // No dialog
    expect(find.text('CLOSE PANEL?'), findsNothing);
    verifyNever(() => tabsBloc.add(const RemovePanel(_panelId)));
  });

  // bail: unknown panelId → no dialog shown ---------------------------------
  testWidgets('unknown panelId: bails silently', (tester) async {
    final p1 = _panel(_panelId, [_tab('t1')]);
    when(() => tabsBloc.state).thenReturn(_state(panels: [p1]));

    final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => false);

    await tester.pumpWidget(
      _host(
        tester,
        tabsBloc: tabsBloc,
        collectionsBloc: collectionsBloc,
        dirtyChecker: dirtyChecker,
        panelId: 'does-not-exist',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
    await tester.pumpAndSettle();

    expect(find.text('CLOSE PANEL?'), findsNothing);
    verifyNever(() => tabsBloc.add(any(that: isA<RemovePanel>())));
  });

  // (new) unlinked tab: SAVE → CONFIRM name prompt → RemovePanel -----------
  testWidgets(
    'dirty + REVIEW & SAVE: unlinked tab, confirm name prompt → '
    'SaveRequestToCollection + UpdateTab + RemovePanel',
    (tester) async {
      // Tab with no collectionNodeId (unlinked)
      final tab1 = _tab('t1');
      final p1 = _panel(_panelId, [tab1]);
      final p2 = _panel(_panel2Id, [_tab('t2')]);
      when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

      final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => true);

      await tester.pumpWidget(
        _host(
          tester,
          tabsBloc: tabsBloc,
          collectionsBloc: collectionsBloc,
          dirtyChecker: dirtyChecker,
          panelId: _panelId,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
      await tester.pumpAndSettle();

      // Summary dialog → REVIEW & SAVE
      await tester.tap(find.text('REVIEW & SAVE…'));
      await tester.pumpAndSettle();

      // Per-tab dialog → SAVE
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      // Name prompt appears — clear pre-filled text, enter a name, confirm
      expect(find.byKey(const ValueKey('name_prompt_field')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('name_prompt_field')),
        'My New Request',
      );
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      // SaveRequestToCollection and UpdateTab must have been dispatched
      verify(
        () => collectionsBloc.add(any(that: isA<SaveRequestToCollection>())),
      ).called(1);
      verify(
        () => tabsBloc.add(any(that: isA<UpdateTab>())),
      ).called(1);

      // Panel must be closed
      verify(() => tabsBloc.add(const RemovePanel(_panelId))).called(1);
    },
  );

  // (new) unlinked tab: SAVE → CANCEL name prompt → panel stays ------------
  testWidgets(
    'dirty + REVIEW & SAVE: unlinked tab, cancel name prompt → '
    'no SaveRequestToCollection and no RemovePanel',
    (tester) async {
      // Tab with no collectionNodeId (unlinked)
      final tab1 = _tab('t1');
      final p1 = _panel(_panelId, [tab1]);
      final p2 = _panel(_panel2Id, [_tab('t2')]);
      when(() => tabsBloc.state).thenReturn(_state(panels: [p1, p2]));

      final dirtyChecker = _FakeDirtyChecker(isDirty: (_) => true);

      await tester.pumpWidget(
        _host(
          tester,
          tabsBloc: tabsBloc,
          collectionsBloc: collectionsBloc,
          dirtyChecker: dirtyChecker,
          panelId: _panelId,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
      await tester.pumpAndSettle();

      // Summary dialog → REVIEW & SAVE
      await tester.tap(find.text('REVIEW & SAVE…'));
      await tester.pumpAndSettle();

      // Per-tab dialog → SAVE
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      // Name prompt appears — CANCEL it
      expect(find.byKey(const ValueKey('name_prompt_field')), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      // No save dispatched to collectionsBloc
      verifyNever(
        () => collectionsBloc.add(any(that: isA<SaveRequestToCollection>())),
      );
      // Panel must NOT be closed
      verifyNever(() => tabsBloc.add(const RemovePanel(_panelId)));
    },
  );
}

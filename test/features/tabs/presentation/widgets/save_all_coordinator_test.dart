// Unit tests for the save-all planner + snackbar message (A3), plus a widget
// test for the coordinator's dispatch path. Pure — no widget pumping:
// planSaveAllTabs walks all panels, picking dirty LINKED tabs whose node
// still exists; dirty unlinked (and stale-linked) tabs are counted as
// skipped; clean tabs are ignored entirely. The widget test drives
// saveAllTabs end-to-end against mocked TabsBloc/CollectionsBloc, verifying
// one UpdateNodeRequest per dirty linked tab and the resulting snackbar text.
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
import 'package:getman/features/tabs/presentation/widgets/save_all_coordinator.dart';
import 'package:mocktail/mocktail.dart';

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

void main() {
  const savedA = HttpRequestConfigEntity(id: 'ca', url: 'https://a.dev');
  const savedB = HttpRequestConfigEntity(id: 'cb', url: 'https://b.dev');
  const savedConfigs = <String, HttpRequestConfigEntity>{
    'na': savedA,
    'nb': savedB,
  };

  const linkedDirtyA = HttpRequestTabEntity(
    tabId: 't1',
    config: HttpRequestConfigEntity(id: 'ca', url: 'https://a.dev/EDIT'),
    collectionNodeId: 'na',
  );
  const linkedCleanB = HttpRequestTabEntity(
    tabId: 't2',
    config: savedB,
    collectionNodeId: 'nb',
  );
  const linkedDirtyB = HttpRequestTabEntity(
    tabId: 't3',
    config: HttpRequestConfigEntity(id: 'cb', url: 'https://b.dev/EDIT'),
    collectionNodeId: 'nb',
  );
  const unlinkedDirty = HttpRequestTabEntity(
    tabId: 't4',
    config: HttpRequestConfigEntity(id: 't4', url: 'https://scratch.dev'),
  );
  const unlinkedPristine = HttpRequestTabEntity(
    tabId: 't5',
    config: HttpRequestConfigEntity(id: 't5'),
  );
  // Linked to a node that no longer exists → dirty but unsaveable in bulk.
  const staleLinked = HttpRequestTabEntity(
    tabId: 't6',
    config: HttpRequestConfigEntity(id: 'cz', url: 'https://z.dev'),
    collectionNodeId: 'gone',
  );

  group('planSaveAllTabs', () {
    test('picks dirty linked tabs across ALL panels; skips dirty unlinked '
        'and stale-linked; ignores clean tabs', () {
      const panels = [
        PanelEntity(
          id: 'p1',
          name: 'P1',
          tabs: [linkedDirtyA, linkedCleanB, unlinkedDirty],
          activeTabId: 't1',
        ),
        PanelEntity(
          id: 'p2',
          name: 'P2',
          tabs: [linkedDirtyB, unlinkedPristine, staleLinked],
          activeTabId: 't3',
        ),
      ];

      final plan = planSaveAllTabs(panels: panels, savedConfigs: savedConfigs);

      expect(
        plan.toSave.map((e) => e.nodeId).toList(),
        ['na', 'nb'],
        reason: 'one save per dirty linked tab, panel order',
      );
      expect(plan.toSave.first.config.url, 'https://a.dev/EDIT');
      expect(plan.skippedCount, 2, reason: 'unlinkedDirty + staleLinked');
    });

    test('no dirty tabs → empty plan', () {
      const panels = [
        PanelEntity(
          id: 'p1',
          name: 'P1',
          tabs: [linkedCleanB, unlinkedPristine],
          activeTabId: 't2',
        ),
      ];
      final plan = planSaveAllTabs(panels: panels, savedConfigs: savedConfigs);
      expect(plan.toSave, isEmpty);
      expect(plan.skippedCount, 0);
    });
  });

  group('saveAllSnackBarMessage', () {
    test('spec strings', () {
      expect(
        saveAllSnackBarMessage(savedCount: 4, skippedCount: 2),
        'Saved 4 requests · 2 unlinked tabs skipped',
      );
      expect(
        saveAllSnackBarMessage(savedCount: 1, skippedCount: 0),
        'Saved 1 request',
      );
      expect(
        saveAllSnackBarMessage(savedCount: 2, skippedCount: 1),
        'Saved 2 requests · 1 unlinked tab skipped',
      );
      expect(
        saveAllSnackBarMessage(savedCount: 0, skippedCount: 0),
        'Nothing to save',
      );
      expect(
        saveAllSnackBarMessage(savedCount: 0, skippedCount: 2),
        'Nothing to save · 2 unlinked tabs skipped',
      );
    });
  });

  group('saveAllTabs (widget)', () {
    setUpAll(() {
      registerFallbackValue(_FakeCollectionsEvent());
      registerFallbackValue(const HttpRequestConfigEntity(id: 'fallback'));
    });

    testWidgets(
      'dispatches one UpdateNodeRequest per dirty linked tab and shows the '
      'count snackbar',
      (tester) async {
        final tabsBloc = _MockTabsBloc();
        final collectionsBloc = _MockCollectionsBloc();
        when(() => collectionsBloc.add(any())).thenReturn(null);

        // 'na' and 'nb' are real saved nodes; configById derives from these.
        when(() => collectionsBloc.state).thenReturn(
          CollectionsState(
            collections: const [
              CollectionNodeEntity(id: 'na', name: 'A', config: savedA),
              CollectionNodeEntity(id: 'nb', name: 'B', config: savedB),
            ],
          ),
        );

        const panel = PanelEntity(
          id: 'p1',
          name: 'P1',
          tabs: [linkedDirtyA, linkedCleanB, unlinkedDirty],
          activeTabId: 't1',
        );
        when(() => tabsBloc.state).thenReturn(
          const TabsState(
            panels: [panel],
            activePanelId: 'p1',
            tabs: [linkedDirtyA, linkedCleanB, unlinkedDirty],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: resolveTheme('brutalist')(
              Brightness.light,
              isCompact: false,
            ),
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<TabsBloc>.value(value: tabsBloc),
                  BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
                  RepositoryProvider<TabDirtyChecker>.value(
                    value: const TabDirtyChecker(),
                  ),
                ],
                child: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      key: const ValueKey('save_all_trigger'),
                      onPressed: () => saveAllTabs(context),
                      child: const Text('Save All'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('save_all_trigger')));
        await tester.pump();

        // Dispatches for the dirty linked tab ('na') — not the clean linked
        // tab ('nb') or the dirty unlinked tab; the snackbar's "1 request ·
        // 1 skipped" (asserted below) corroborates no other dispatch fired.
        verify(
          () => collectionsBloc.add(
            UpdateNodeRequest('na', linkedDirtyA.config.copyWith()),
          ),
        ).called(1);

        expect(
          find.text('Saved 1 request · 1 unlinked tab skipped'),
          findsOneWidget,
        );
      },
    );
  });
}

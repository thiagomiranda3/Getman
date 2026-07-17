import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/widgets/node_drag_data.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/panel_selector.dart';
import 'package:getman/features/tabs/presentation/widgets/tab_drag_data.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

const String _workPanelId = 'p2';

HttpRequestTabEntity _tab(String id) => HttpRequestTabEntity(
  tabId: id,
  config: HttpRequestConfigEntity(id: id),
);

PanelEntity _panel(String id, String name, List<String> tabIds) => PanelEntity(
  id: id,
  name: name,
  tabs: [for (final t in tabIds) _tab(t)],
  activeTabId: tabIds.first,
);

TabsState _twoPanelState() {
  final p1 = _panel('p1', 'Panel 1', ['t1']);
  final work = _panel(_workPanelId, 'Work', ['t2', 't3']);
  return TabsState(panels: [p1, work], activePanelId: 'p1', tabs: p1.tabs);
}

Widget _host(TabsBloc bloc) {
  return MaterialApp(
    theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
    home: Scaffold(
      body: BlocProvider<TabsBloc>.value(
        value: bloc,
        child: const Align(child: PanelSelector()),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
  });

  late MockTabsBloc bloc;

  setUp(() {
    bloc = MockTabsBloc();
    when(() => bloc.state).thenReturn(_twoPanelState());
  });

  testWidgets('shows the active panel name', (tester) async {
    await tester.pumpWidget(_host(bloc));
    expect(find.text('Panel 1'), findsOneWidget);
  });

  testWidgets('shows active panel name and switches on selection', (
    tester,
  ) async {
    await tester.pumpWidget(_host(bloc));
    expect(find.text('Panel 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('panel_selector_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('panel_row_$_workPanelId')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const SetActivePanel(_workPanelId))).called(1);
  });

  testWidgets('new panel footer dispatches AddPanel', (tester) async {
    await tester.pumpWidget(_host(bloc));
    await tester.tap(find.byKey(const ValueKey('panel_selector_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('panel_add_button')));
    await tester.pumpAndSettle();
    verify(() => bloc.add(const AddPanel())).called(1);
  });

  testWidgets('double-tap the name opens rename', (tester) async {
    await tester.pumpWidget(_host(bloc));
    final gesture = find.byKey(const ValueKey('panel_selector_button'));
    await tester.tap(gesture);
    // A frame MUST be pumped between the two taps: the first tap opens an
    // overlay whose full-screen barrier sits on top of the button, so a real
    // double-tap's second tap physically hits the barrier, not the button.
    // Without this pump the overlay never gets a layout pass, so the second
    // tap still (incorrectly) reaches the button's own GestureDetector — that
    // false positive is what let the D1 bug ship undetected.
    await tester.pump();
    // The second tap physically lands on the menu's dismiss barrier (which
    // now covers the button) rather than the button's own GestureDetector —
    // that's the whole point of the fix, so the "missed" hit-test warning is
    // expected here.
    await tester.tap(gesture, warnIfMissed: false); // double
    await tester.pumpAndSettle();
    expect(find.text('RENAME PANEL'), findsOneWidget);
  });

  testWidgets('rename dialog dispatches RenamePanel for the active panel', (
    tester,
  ) async {
    await tester.pumpWidget(_host(bloc));
    final gesture = find.byKey(const ValueKey('panel_selector_button'));
    await tester.tap(gesture);
    await tester.pump(); // see comment above — a real double-tap hits the
    // barrier on its second tap, which requires the overlay to be laid out.
    // The second tap physically lands on the menu's dismiss barrier (which
    // now covers the button) rather than the button's own GestureDetector —
    // that's the whole point of the fix, so the "missed" hit-test warning is
    // expected here.
    await tester.tap(gesture, warnIfMissed: false); // double
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('name_prompt_field')),
      'Renamed',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const RenamePanel('p1', 'Renamed'))).called(1);
  });

  testWidgets(
    'dropping a tab onto selector opens menu; tapping a panel row dispatches '
    'MoveTabToPanel',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<TabsBloc>.value(
              value: bloc,
              child: const Row(
                children: [
                  LongPressDraggable<TabDragData>(
                    key: ValueKey('drag_source'),
                    data: TabDragData('t1'),
                    feedback: Material(child: Text('t1')),
                    child: SizedBox(
                      width: 100,
                      height: 50,
                      child: ColoredBox(
                        color: Colors.blue,
                        child: Text('drag me'),
                      ),
                    ),
                  ),
                  PanelSelector(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Long-press to start drag, move to selector, release.
      final sourceCenter = tester.getCenter(
        find.byKey(const ValueKey('drag_source')),
      );
      final targetCenter = tester.getCenter(
        find.byKey(const ValueKey('panel_selector_button')),
      );
      final gesture = await tester.startGesture(sourceCenter);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(targetCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Panel menu should now be open in "move" mode.
      // Tap the 'Work' panel row (id: _workPanelId = 'p2').
      await tester.tap(
        find.byKey(const ValueKey('panel_row_$_workPanelId')),
      );
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(const MoveTabToPanel('t1', _workPanelId)),
      ).called(1);
    },
  );

  testWidgets(
    'dropping a tab onto selector and tapping add-footer dispatches '
    'MoveTabToNewPanel',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<TabsBloc>.value(
              value: bloc,
              child: const Row(
                children: [
                  LongPressDraggable<TabDragData>(
                    key: ValueKey('drag_source2'),
                    data: TabDragData('t1'),
                    feedback: Material(child: Text('t1')),
                    child: SizedBox(
                      width: 100,
                      height: 50,
                      child: ColoredBox(
                        color: Colors.green,
                        child: Text('drag me'),
                      ),
                    ),
                  ),
                  PanelSelector(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sourceCenter = tester.getCenter(
        find.byKey(const ValueKey('drag_source2')),
      );
      final targetCenter = tester.getCenter(
        find.byKey(const ValueKey('panel_selector_button')),
      );
      final gesture = await tester.startGesture(sourceCenter);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(targetCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap the "New panel" footer — should dispatch MoveTabToNewPanel.
      await tester.tap(find.byKey(const ValueKey('panel_add_button')));
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(const MoveTabToNewPanel('t1')),
      ).called(1);
    },
  );

  testWidgets(
    'D4: a collection-node drag (NodeDragData) is rejected by the panel '
    'selector — no menu opens, no bloc event dispatched',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<TabsBloc>.value(
              value: bloc,
              child: const Row(
                children: [
                  LongPressDraggable<NodeDragData>(
                    key: ValueKey('node_drag_source'),
                    data: NodeDragData('node-1'),
                    feedback: Material(child: Text('node-1')),
                    child: SizedBox(
                      width: 100,
                      height: 50,
                      child: ColoredBox(
                        color: Colors.orange,
                        child: Text('drag me'),
                      ),
                    ),
                  ),
                  PanelSelector(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sourceCenter = tester.getCenter(
        find.byKey(const ValueKey('node_drag_source')),
      );
      final targetCenter = tester.getCenter(
        find.byKey(const ValueKey('panel_selector_button')),
      );
      final gesture = await tester.startGesture(sourceCenter);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(targetCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // A foreign (node) payload must not be accepted by the tab-drop target:
      // no menu opens and no move event fires.
      expect(
        find.byKey(const ValueKey('panel_row_$_workPanelId')),
        findsNothing,
      );
      verifyNever(() => bloc.add(any(that: isA<MoveTabToPanel>())));
      verifyNever(() => bloc.add(any(that: isA<MoveTabToNewPanel>())));
    },
  );

  testWidgets(
    'D2: two accepted drops in a row do not leave the first menu overlay '
    'orphaned (which would permanently soft-lock input behind its '
    'full-screen barrier)',
    (tester) async {
      // Once a menu is open, its full-screen barrier covers the selector
      // button itself, so a *second* real drag-and-drop gesture can never
      // physically reach the DragTarget again — realistic user input can't
      // exercise the reentrancy this guards against. Instead, invoke the
      // DragTarget's accept callback directly twice in a row (the same
      // technique collection_node_row_test.dart uses), which calls
      // `_openMenu` exactly as `onTabDropped` would.
      await tester.pumpWidget(_host(bloc));
      await tester.pumpAndSettle();

      final dragTarget = tester.widget<DragTarget<TabDragData>>(
        find.byType(DragTarget<TabDragData>),
      );

      dragTarget.onAcceptWithDetails!(
        DragTargetDetails<TabDragData>(
          data: const TabDragData('t1'),
          offset: Offset.zero,
        ),
      );
      await tester.pump();
      dragTarget.onAcceptWithDetails!(
        DragTargetDetails<TabDragData>(
          data: const TabDragData('t1'),
          offset: Offset.zero,
        ),
      );
      await tester.pump();

      // Exactly one copy of the menu is mounted — the first drop's overlay
      // must have been removed (not orphaned) before the second was opened.
      expect(
        find.byKey(const ValueKey('panel_row_$_workPanelId')),
        findsOneWidget,
      );
    },
  );
}

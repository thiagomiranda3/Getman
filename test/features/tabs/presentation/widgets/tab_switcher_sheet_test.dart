import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/tab_switcher_sheet.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

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

/// Pumps [TabSwitcherSheet] directly (no modal), inside a standard
/// desktop-width viewport so dialogs render as centered modals.
Future<void> _pumpSheet(
  WidgetTester tester,
  TabsBloc bloc, {
  TabsState? state,
  Future<bool> Function(String tabId)? onRequestClose,
}) async {
  final effectiveState = state ?? _twoPanelState();
  when(() => bloc.state).thenReturn(effectiveState);

  await tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
      home: Scaffold(
        body: BlocProvider<TabsBloc>.value(
          value: bloc,
          child: TabSwitcherSheet(
            onRequestClose: onRequestClose ?? (_) async => true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the sheet through the real [TabSwitcherSheet.show] modal path, so
/// row taps / footer buttons that pop the route can be asserted against.
Future<void> _pumpModal(
  WidgetTester tester,
  TabsBloc bloc, {
  TabsState? state,
}) async {
  when(() => bloc.state).thenReturn(state ?? _twoPanelState());

  await tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
      home: Scaffold(
        body: BlocProvider<TabsBloc>.value(
          value: bloc,
          child: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => TabSwitcherSheet.show(
                  context,
                  onRequestClose: (_) async => true,
                ),
                child: const Text('OPEN SHEET'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN SHEET'));
  await tester.pumpAndSettle();
}

TabsState _twoPanelState() {
  final p1 = _panel('p1', 'Panel 1', ['t1']);
  final p2 = _panel('p2', 'Work', ['t2', 't3']);
  return TabsState(panels: [p1, p2], activePanelId: 'p1', tabs: p1.tabs);
}

TabsState _onePanelState() {
  final p1 = _panel('p1', 'Panel 1', ['t1', 't2']);
  return TabsState(panels: [p1], activePanelId: 'p1', tabs: p1.tabs);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
  });

  late MockTabsBloc bloc;

  setUp(() {
    bloc = MockTabsBloc();
  });

  group('panel row — chips', () {
    testWidgets('shows a chip for each panel', (tester) async {
      await _pumpSheet(tester, bloc);

      expect(find.byKey(const ValueKey('panel_chip_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('panel_chip_p2')), findsOneWidget);
    });

    testWidgets('shows + New panel chip', (tester) async {
      await _pumpSheet(tester, bloc);

      expect(find.byKey(const ValueKey('sheet_add_panel')), findsOneWidget);
    });

    testWidgets('tapping a panel chip dispatches SetActivePanel', (
      tester,
    ) async {
      await _pumpSheet(tester, bloc);

      // Tap the panel name text inside the chip.
      // Use a 500 ms pump to let the double-tap window expire before verify.
      await tester.tap(find.text('Work'));
      await tester.pump(const Duration(milliseconds: 500));

      verify(() => bloc.add(const SetActivePanel('p2'))).called(1);
    });

    testWidgets('tapping + New panel chip dispatches AddPanel', (tester) async {
      await _pumpSheet(tester, bloc);

      await tester.tap(find.byKey(const ValueKey('sheet_add_panel')));
      await tester.pumpAndSettle();

      verify(() => bloc.add(const AddPanel())).called(1);
    });

    testWidgets('each panel chip shows a pencil rename icon', (tester) async {
      await _pumpSheet(tester, bloc);

      // There should be one edit icon per panel chip (2 panels → 2 icons).
      expect(find.byIcon(Icons.edit), findsNWidgets(2));
    });

    testWidgets(
      'empty rename submission dispatches RenamePanel with empty string',
      (tester) async {
        await _pumpSheet(tester, bloc);

        // Open the rename dialog for p1 via the edit icon inside the p1 chip.
        final editButton = find.byIcon(Icons.edit).first;
        await tester.ensureVisible(editButton);
        await tester.tap(editButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify the dialog is open before proceeding.
        expect(find.text('RENAME PANEL'), findsOneWidget);

        // The dialog is open — clear whatever initial text is pre-filled.
        await tester.enterText(
          find.byKey(const ValueKey('name_prompt_field')),
          '',
        );
        await tester.pumpAndSettle();

        // With allowEmpty: true the SAVE button must be enabled — tap it.
        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        // The bloc should have received RenamePanel with an empty name.
        // The bloc itself resets empty names to "Panel N"; at this layer we
        // only verify that the event is dispatched with the empty string.
        verify(() => bloc.add(const RenamePanel('p1', ''))).called(1);
      },
    );
  });

  group('move to panel affordance', () {
    testWidgets('shows move-to-panel button when 2+ panels exist', (
      tester,
    ) async {
      await _pumpSheet(tester, bloc);

      expect(
        find.byKey(const ValueKey('tab_move_panel_t1')),
        findsOneWidget,
      );
    });

    testWidgets('does NOT show move-to-panel button when only 1 panel', (
      tester,
    ) async {
      await _pumpSheet(tester, bloc, state: _onePanelState());

      expect(
        find.byKey(const ValueKey('tab_move_panel_t1')),
        findsNothing,
      );
    });

    testWidgets(
      'tapping a panel item in the move popup dispatches MoveTabToPanel',
      (tester) async {
        await _pumpSheet(tester, bloc);

        // Open the move popup for tab t1
        await tester.tap(find.byKey(const ValueKey('tab_move_panel_t1')));
        await tester.pumpAndSettle();

        // Tap the 'Work' (p2) panel option
        await tester.tap(find.byKey(const ValueKey('tab_move_to_panel_p2')));
        await tester.pumpAndSettle();

        verify(() => bloc.add(const MoveTabToPanel('t1', 'p2'))).called(1);
      },
    );

    testWidgets(
      'tapping New panel item in the move popup dispatches MoveTabToNewPanel',
      (tester) async {
        await _pumpSheet(tester, bloc);

        // Open the move popup for tab t1
        await tester.tap(find.byKey(const ValueKey('tab_move_panel_t1')));
        await tester.pumpAndSettle();

        // Tap the 'NEW PANEL' option
        await tester.tap(
          find.byKey(const ValueKey('tab_move_to_new_panel_t1')),
        );
        await tester.pumpAndSettle();

        verify(() => bloc.add(const MoveTabToNewPanel('t1'))).called(1);
      },
    );

    testWidgets(
      'move popup excludes the owning panel; other panels + New panel present',
      (tester) async {
        // Two-panel state: p1 is active and owns t1; p2 owns t2/t3.
        await _pumpSheet(tester, bloc);

        // Open the move popup for t1 (owned by p1).
        await tester.tap(find.byKey(const ValueKey('tab_move_panel_t1')));
        await tester.pumpAndSettle();

        // The owning panel (p1 / 'Panel 1') must NOT appear as a destination.
        expect(
          find.byKey(const ValueKey('tab_move_to_panel_p1')),
          findsNothing,
        );
        // The other panel (p2 / 'Work') MUST appear.
        expect(
          find.byKey(const ValueKey('tab_move_to_panel_p2')),
          findsOneWidget,
        );
        // The 'New panel' entry must still be present.
        expect(
          find.byKey(const ValueKey('tab_move_to_new_panel_t1')),
          findsOneWidget,
        );
      },
    );
  });

  group('tab list', () {
    testWidgets('shows tabs from the active panel', (tester) async {
      await _pumpSheet(tester, bloc);

      expect(
        find.byKey(const ValueKey('switcher_t1')),
        findsOneWidget,
      );
    });

    testWidgets('shows NO OPEN TABS when tab list is empty', (tester) async {
      final p1 = _panel('p1', 'Panel 1', ['t1']);
      // Override tabs to empty (bloc serves a state with no active-panel tabs)
      final emptyState = TabsState(
        panels: [p1],
        activePanelId: 'p1',
      );
      await _pumpSheet(tester, bloc, state: emptyState);

      expect(find.text('NO OPEN TABS'), findsOneWidget);
    });

    testWidgets(
      'row close button dispatches RemoveTab when the close is confirmed',
      (tester) async {
        await _pumpSheet(tester, bloc);

        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('switcher_t1')),
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        verify(() => bloc.add(const RemoveTab('t1'))).called(1);
      },
    );

    testWidgets(
      'row close button is a no-op when onRequestClose declines',
      (tester) async {
        await _pumpSheet(tester, bloc, onRequestClose: (_) async => false);

        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('switcher_t1')),
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        verifyNever(() => bloc.add(const RemoveTab('t1')));
      },
    );

    testWidgets('dragging the row handle dispatches ReorderTabs', (
      tester,
    ) async {
      await _pumpSheet(tester, bloc, state: _onePanelState());

      final handle = find.descendant(
        of: find.byKey(const ValueKey('switcher_t1')),
        matching: find.byIcon(Icons.drag_handle),
      );
      // Drag row t1 well below row t2, with settled frames between moves so
      // the ReorderableListView registers the displacement.
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      final captured = verify(() => bloc.add(captureAny())).captured;
      expect(
        captured.whereType<ReorderTabs>(),
        isNotEmpty,
        reason: 'the drag handle must dispatch a ReorderTabs event',
      );
    });
  });

  group('modal show() path', () {
    testWidgets(
      'tapping a tab row dispatches SetActiveIndex and dismisses the sheet',
      (tester) async {
        await _pumpModal(tester, bloc);
        expect(find.byType(TabSwitcherSheet), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('switcher_t1')));
        await tester.pumpAndSettle();

        verify(() => bloc.add(const SetActiveIndex(0))).called(1);
        expect(find.byType(TabSwitcherSheet), findsNothing);
      },
    );

    testWidgets(
      'NEW TAB footer dispatches AddTab and dismisses the sheet',
      (tester) async {
        await _pumpModal(tester, bloc);

        await tester.tap(find.text('NEW TAB'));
        await tester.pumpAndSettle();

        verify(() => bloc.add(const AddTab())).called(1);
        expect(find.byType(TabSwitcherSheet), findsNothing);
      },
    );

    testWidgets(
      'CLOSE footer dismisses the sheet without dispatching anything',
      (tester) async {
        await _pumpModal(tester, bloc);

        await tester.tap(find.text('CLOSE'));
        await tester.pumpAndSettle();

        expect(find.byType(TabSwitcherSheet), findsNothing);
        verifyNever(() => bloc.add(any()));
      },
    );
  });
}

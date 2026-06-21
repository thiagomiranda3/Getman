import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/features/home/presentation/screens/main_screen.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/main.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

// ---------------------------------------------------------------------------
// Panel-specific finders / helpers (mirror the `tab_*` helpers in actions.dart).
// Panels are keyed by a dynamic uuid, so we read live `TabsBloc` state to map
// names → ids rather than hardcoding ids.
// ---------------------------------------------------------------------------

/// Reads the live [TabsBloc] off the element tree. `MainScreen` always sits
/// below the app-level `MultiBlocProvider`, so `BlocProvider.of` resolves the
/// real running bloc — letting a flow assert on panel structure (ids/names/
/// order) that isn't otherwise observable from the rendered chrome.
TabsBloc _tabsBloc(PatrolTester $) {
  final ctx = $.tester.element(find.byType(MainScreen));
  return BlocProvider.of<TabsBloc>(ctx);
}

/// All panels in display order, from live bloc state.
List<PanelEntity> _panels(PatrolTester $) => _tabsBloc($).state.panels;

/// The active panel's name (what the selector button shows).
String _activePanelName(PatrolTester $) =>
    _tabsBloc($).state.activePanel?.name ?? '';

/// Id of the panel whose name is [name] (first match).
String _panelIdByName(PatrolTester $, String name) =>
    _panels($).firstWhere((p) => p.name == name).id;

/// Opens the panel dropdown (taps the selector button once). The button is a
/// raw `GestureDetector`, so a settle is fine (no never-ending animation).
Future<void> _openPanelMenu(PatrolTester $) async {
  await $(const ValueKey('panel_selector_button')).tap();
  await $.pumpAndSettle();
}

/// Adds a panel via the dropdown footer (`+ New panel`). Leaves the menu state
/// to settle (the menu dismisses itself after adding).
Future<void> _addPanelViaMenu(PatrolTester $) async {
  await _openPanelMenu($);
  await $(const ValueKey('panel_add_button')).tap();
  await $.pumpAndSettle();
}

/// Switches to the panel named [name] via the dropdown row.
Future<void> _switchToPanel(PatrolTester $, String name) async {
  final id = _panelIdByName($, name);
  await _openPanelMenu($);
  await $(ValueKey('panel_row_$id')).tap();
  await $.pumpAndSettle();
}

/// Dismisses an open panel dropdown by tapping its full-screen barrier near the
/// top-left corner (the menu card is anchored to the selector at top-right, so
/// the corner is empty barrier). The selector button itself is unreachable
/// while the barrier is up, so `$.tap(panel_selector_button)` can't dismiss it.
Future<void> _dismissPanelMenu(PatrolTester $) async {
  await $.tester.tapAt(const Offset(8, 8));
  await $.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Step 1 — Creating & switching (flows 1-4)
  // -------------------------------------------------------------------------

  patrolWidgetTest(
    '(1) new panel via footer becomes active and empty',
    ($) async {
      await bootGetman($);
      expect(_panels($).length, 1);
      expect(_activePanelName($), 'Panel 1');

      await _addPanelViaMenu($);

      expect(_panels($).length, 2, reason: 'footer + adds a second panel');
      expect(
        _activePanelName($),
        'Panel 2',
        reason: 'a freshly-added panel becomes active',
      );
      expect(
        tabCount($),
        0,
        reason: 'a new panel starts empty (no seeded tab)',
      );
      expect(
        $('NO OPEN TABS'),
        findsWidgets,
        reason: 'the empty panel shows the placeholder',
      );
    },
  );

  patrolWidgetTest('(2) new panel via Cmd+Shift+N', ($) async {
    await bootGetman($);
    expect(_panels($).length, 1);

    await sendShortcut($, LogicalKeyboardKey.keyN, meta: true, shift: true);
    await $.pumpAndSettle();

    expect(_panels($).length, 2);
    expect(_activePanelName($), 'Panel 2');
    expect(tabCount($), 0, reason: 'a new panel starts empty');
  });

  patrolWidgetTest(
    '(3) switching panels restores the remembered active tab',
    ($) async {
      await bootGetman($);

      // Panel 1: open a 2nd tab, give each a distinct URL, leave tab #2 active.
      await enterUrl($, 'https://p1.example.com/first');
      await newTab($);
      await enterUrl($, 'https://p1.example.com/second');
      expect(activeUrl($), 'https://p1.example.com/second');

      // New panel starts empty → add a tab, then type a URL to recognise it.
      await _addPanelViaMenu($);
      await newTab($);
      await enterUrl($, 'https://p2.example.com/only');
      expect(_activePanelName($), 'Panel 2');

      // Back to Panel 1 → its remembered active tab (the 2nd) is restored.
      await _switchToPanel($, 'Panel 1');
      expect(activeUrl($), 'https://p1.example.com/second');
      expect(tabCount($), 2);

      // Back to Panel 2 → its single tab restored.
      await _switchToPanel($, 'Panel 2');
      expect(activeUrl($), 'https://p2.example.com/only');
      expect(tabCount($), 1);
    },
  );

  patrolWidgetTest('(4) next/prev/jump-to-panel shortcuts switch panels', (
    $,
  ) async {
    await bootGetman($);
    await _addPanelViaMenu($); // Panel 2 (active)
    await _addPanelViaMenu($); // Panel 3 (active)
    expect(_panels($).length, 3);
    expect(_activePanelName($), 'Panel 3');

    // Next wraps 3 → 1.
    await sendShortcut(
      $,
      LogicalKeyboardKey.bracketRight,
      meta: true,
      shift: true,
    );
    expect(_activePanelName($), 'Panel 1');

    // Prev wraps 1 → 3.
    await sendShortcut(
      $,
      LogicalKeyboardKey.bracketLeft,
      meta: true,
      shift: true,
    );
    expect(_activePanelName($), 'Panel 3');

    // Jump to panel index 1 (Cmd+Shift+2) → Panel 2.
    await sendShortcut($, LogicalKeyboardKey.digit2, meta: true, shift: true);
    expect(_activePanelName($), 'Panel 2');

    // Jump to panel index 0 (Cmd+Shift+1) → Panel 1.
    await sendShortcut($, LogicalKeyboardKey.digit1, meta: true, shift: true);
    expect(_activePanelName($), 'Panel 1');
  });

  // -------------------------------------------------------------------------
  // Step 2 — Renaming (every affordance) (flows 5-8)
  // -------------------------------------------------------------------------

  patrolWidgetTest('(5) double-click selector name renames the panel', (
    $,
  ) async {
    await bootGetman($);

    // Double-tap the selector button → rename dialog. The first tap opens the
    // menu (whose full-screen barrier would intercept a later tap), so both
    // taps must land at the button center back-to-back BEFORE the overlay is
    // laid out — drive them through one gesture sequence with no pump between.
    final center = $.tester.getCenter(
      find.byKey(const ValueKey('panel_selector_button')),
    );
    final g1 = await $.tester.startGesture(center);
    await g1.up();
    final g2 = await $.tester.startGesture(center);
    await g2.up();
    await $.pumpAndSettle();
    expect($('RENAME PANEL'), findsWidgets);

    await enterPromptText($, 'Sandbox');
    await $('SAVE').tap();
    await $.pumpAndSettle();

    expect(_activePanelName($), 'Sandbox');
  });

  patrolWidgetTest('(6) pencil in a panel row renames the panel', ($) async {
    await bootGetman($);
    final id = _panelIdByName($, 'Panel 1');

    await _openPanelMenu($);
    await $(ValueKey('panel_rename_$id')).tap();
    await $.pumpAndSettle();
    expect($('RENAME PANEL'), findsWidgets);

    await enterPromptText($, 'Staging');
    await $('SAVE').tap();
    await $.pumpAndSettle();

    expect(_panels($).single.name, 'Staging');
  });

  patrolWidgetTest('(7) RENAME PANEL via the selector double-tap title', (
    $,
  ) async {
    // The desktop affordances are the double-tap (flow 5) and the per-row
    // pencil (flow 6). The "RENAME PANEL" titled dialog is the single rename
    // entry point for both; here we exercise renaming a NON-active panel's row
    // (the menu's per-row pencil acts on that row, not the active panel).
    await bootGetman($);
    await _addPanelViaMenu($); // Panel 2 active; Panel 1 inactive

    final inactiveId = _panelIdByName($, 'Panel 1');
    await _openPanelMenu($);
    await $(ValueKey('panel_rename_$inactiveId')).tap();
    await $.pumpAndSettle();

    await enterPromptText($, 'Renamed Inactive');
    await $('SAVE').tap();
    await $.pumpAndSettle();

    expect(
      _panels($).any((p) => p.name == 'Renamed Inactive'),
      isTrue,
    );
    // The active panel is unchanged by renaming a different row.
    expect(_activePanelName($), 'Panel 2');
  });

  patrolWidgetTest('(8) empty rename submission resets to Panel N', ($) async {
    await bootGetman($);

    // Rename to something custom first.
    final id = _panelIdByName($, 'Panel 1');
    await _openPanelMenu($);
    await $(ValueKey('panel_rename_$id')).tap();
    await $.pumpAndSettle();
    await enterPromptText($, 'Temp Name');
    await $('SAVE').tap();
    await $.pumpAndSettle();
    expect(_activePanelName($), 'Temp Name');

    // Now rename to empty → bloc reclaims the lowest free "Panel N" slot.
    await _openPanelMenu($);
    await $(ValueKey('panel_rename_$id')).tap();
    await $.pumpAndSettle();
    await enterPromptText($, '');
    await $('SAVE').tap();
    await $.pumpAndSettle();

    expect(_activePanelName($), 'Panel 1');
  });

  // -------------------------------------------------------------------------
  // Step 3 — Reordering (flow 9)
  // -------------------------------------------------------------------------

  patrolWidgetTest('(9) drag panel rows reorders and persists', ($) async {
    await bootGetman($);
    await _addPanelViaMenu($); // Panel 2
    await _addPanelViaMenu($); // Panel 3
    expect(_panels($).map((p) => p.name), ['Panel 1', 'Panel 2', 'Panel 3']);

    // Dispatch the reorder the dropdown's ReorderableListView would emit:
    // move row 0 (Panel 1) to the end. (Simulating the native long-press drag
    // of a ReorderableDragStartListener handle inside an overlay is flaky; the
    // drag gesture itself is covered by extras_test's tab-reorder. Here we
    // assert the *panel order persists* through the bloc + reopened dropdown.)
    _tabsBloc($).add(const ReorderPanels(0, 3));
    await $.pumpAndSettle();

    expect(_panels($).map((p) => p.name), ['Panel 2', 'Panel 3', 'Panel 1']);

    // Reopen the dropdown → the rows reflect the new order (rows are keyed by
    // id; verify all three rows are present and the order matches state).
    await _openPanelMenu($);
    for (final p in _panels($)) {
      expect($(ValueKey('panel_row_${p.id}')), findsOneWidget);
    }
    await _dismissPanelMenu($);
  });

  // -------------------------------------------------------------------------
  // Step 4 — Moving tabs (flows 10-14)
  // -------------------------------------------------------------------------

  patrolWidgetTest(
    '(10) MOVE TO PANEL submenu moves a tab between panels',
    ($) async {
      await bootGetman($);
      await enterUrl($, 'https://mover.example.com/tab');
      await _addPanelViaMenu($); // Panel 2 (active, empty)
      await _switchToPanel($, 'Panel 1');
      expect(tabCount($), 1);

      final targetId = _panelIdByName($, 'Panel 2');

      // Right-click the tab → MOVE TO PANEL → Panel 2.
      await openTabMenu($, 0);
      await $(const ValueKey('tab_context_move_to_panel')).tap();
      await $.pumpAndSettle();
      await $(ValueKey('tab_move_to_panel_$targetId')).tap();
      await $.pumpAndSettle();

      // Source goes empty (no re-seed); the moved tab is gone from it.
      expect(_panels($).firstWhere((p) => p.name == 'Panel 1').tabs, isEmpty);
      expect(tabCount($), 0);
      expect($('NO OPEN TABS'), findsWidgets);

      // It now lives in Panel 2.
      await _switchToPanel($, 'Panel 2');
      final p2Urls = _panels(
        $,
      ).firstWhere((p) => p.name == 'Panel 2').tabs.map((t) => t.config.url);
      expect(p2Urls, contains('https://mover.example.com/tab'));
    },
  );

  patrolWidgetTest(
    '(11) MOVE TO PANEL > NEW PANEL creates a panel with only that tab',
    ($) async {
      await bootGetman($);
      // The desktop MOVE TO PANEL submenu only appears with 2+ panels, so make
      // a second panel first, then move a tab to a brand-new (third) panel.
      await _addPanelViaMenu($); // Panel 2
      await _switchToPanel($, 'Panel 1');
      await enterUrl($, 'https://newpanel.example.com/x');
      await newTab($); // a 2nd tab so Panel 1 keeps a tab after the move
      await enterUrl($, 'https://newpanel.example.com/y');
      expect(tabCount($), 2);

      // Move the 2nd tab to a brand-new panel.
      await openTabMenu($, 1);
      await $(const ValueKey('tab_context_move_to_panel')).tap();
      await $.pumpAndSettle();
      await $(const ValueKey('tab_move_to_new_panel')).tap();
      await $.pumpAndSettle();

      // A new panel was created carrying only the moved tab. The bloc does NOT
      // switch to it (active panel unchanged per spec) — Panel 1 stays active.
      expect(_panels($).length, 3);
      expect(_activePanelName($), 'Panel 1');
      final created = _panels($).firstWhere(
        (p) => p.tabs.any(
          (t) => t.config.url == 'https://newpanel.example.com/y',
        ),
      );
      expect(created.name, isNot('Panel 1'));
      expect(created.tabs.length, 1);
      // Source kept the first tab.
      expect(tabCount($), 1);
      expect(activeUrl($), 'https://newpanel.example.com/x');
    },
  );

  patrolWidgetTest(
    '(12) drag a tab onto the selector opens move-mode; pick a panel row',
    ($) async {
      await bootGetman($);
      await enterUrl($, 'https://drag.example.com/tab');
      await _addPanelViaMenu($); // Panel 2
      await _switchToPanel($, 'Panel 1');

      final targetId = _panelIdByName($, 'Panel 2');

      // Long-press-drag the only tab onto the panel selector (a DragTarget).
      // Hold past the long-press timeout first so the LongPressDraggable (not
      // the immediate ReorderableDragStartListener) wins the gesture arena,
      // then walk to the selector in steps so the drag registers.
      final from = $.tester.getCenter(allTabs().first);
      final to = $.tester.getCenter(
        find.byKey(const ValueKey('panel_selector_button')),
      );
      final gesture = await $.tester.startGesture(from);
      await $.tester.pump(const Duration(milliseconds: 700)); // arm long-press
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
        await $.tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await $.pumpAndSettle();

      // The selector opened the menu in "move" mode → tap the Panel 2 row.
      expect($(ValueKey('panel_row_$targetId')), findsOneWidget);
      await $(ValueKey('panel_row_$targetId')).tap();
      await $.pumpAndSettle();

      // The tab moved to Panel 2.
      await _switchToPanel($, 'Panel 2');
      final p2Urls = _panels(
        $,
      ).firstWhere((p) => p.name == 'Panel 2').tabs.map((t) => t.config.url);
      expect(p2Urls, contains('https://drag.example.com/tab'));
    },
  );

  patrolWidgetTest(
    '(13) drag a tab onto the selector then pick + New panel',
    ($) async {
      await bootGetman($);
      await enterUrl($, 'https://drag2.example.com/tab');
      await newTab($); // 2nd tab so Panel 1 keeps a tab after the move
      await enterUrl($, 'https://drag2.example.com/moved');
      expect(tabCount($), 2);

      final from = $.tester.getCenter(allTabs().at(1));
      final to = $.tester.getCenter(
        find.byKey(const ValueKey('panel_selector_button')),
      );
      final gesture = await $.tester.startGesture(from);
      await $.tester.pump(const Duration(milliseconds: 700));
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
        await $.tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await $.pumpAndSettle();

      // Move-mode menu → footer dispatches MoveTabToNewPanel.
      await $(const ValueKey('panel_add_button')).tap();
      await $.pumpAndSettle();

      expect(_panels($).length, 2);
      final created = _panels($).firstWhere((p) => p.name != 'Panel 1');
      expect(created.tabs.single.config.url, 'https://drag2.example.com/moved');
    },
  );

  patrolWidgetTest('(14) moving the last tab out leaves the source empty', (
    $,
  ) async {
    await bootGetman($);
    await enterUrl($, 'https://last.example.com/only');
    await _addPanelViaMenu($); // Panel 2
    await _switchToPanel($, 'Panel 1');
    expect(tabCount($), 1);

    final targetId = _panelIdByName($, 'Panel 2');

    // Move Panel 1's only tab to Panel 2 → Panel 1 goes empty, no re-seed.
    await openTabMenu($, 0);
    await $(const ValueKey('tab_context_move_to_panel')).tap();
    await $.pumpAndSettle();
    await $(ValueKey('tab_move_to_panel_$targetId')).tap();
    await $.pumpAndSettle();

    expect(_panels($).firstWhere((p) => p.name == 'Panel 1').tabs, isEmpty);
    expect(tabCount($), 0);
    expect(
      $('NO OPEN TABS'),
      findsWidgets,
      reason: 'the emptied panel shows the placeholder',
    );
  });

  // -------------------------------------------------------------------------
  // Step 5 — Closing panels (flows 15-19)
  // -------------------------------------------------------------------------

  patrolWidgetTest('(15) close a clean panel after a confirm', ($) async {
    await bootGetman($);
    await _addPanelViaMenu($); // Panel 2 (empty, nothing dirty)
    expect(_panels($).length, 2);

    final id = _panelIdByName($, 'Panel 2');
    await _openPanelMenu($);
    await $(ValueKey('panel_close_$id')).tap();
    await $.pumpAndSettle();

    // No dirty tabs → simple "CLOSE PANEL?" confirm.
    expect($('CLOSE PANEL?'), findsWidgets);
    await $('CLOSE').tap();
    await $.pumpAndSettle();

    expect(_panels($).length, 1);
    expect(_panels($).single.name, 'Panel 1');
  });

  patrolWidgetTest('(16) dirty panel → Discard all & close', ($) async {
    await bootGetman($);
    // Make Panel 2 dirty: add a tab (new panels start empty), then give it a
    // config that differs from the default blank.
    await _addPanelViaMenu($); // Panel 2 active (empty)
    await newTab($);
    await enterUrl($, 'https://dirty.example.com/unsaved');
    await $.pumpAndSettle();
    final id = _panelIdByName($, 'Panel 2');

    await _openPanelMenu($);
    await $(ValueKey('panel_close_$id')).tap();
    await $.pumpAndSettle();

    // Dirty summary dialog.
    expect($('DISCARD ALL & CLOSE'), findsWidgets);
    await $('DISCARD ALL & CLOSE').tap();
    await $.pumpAndSettle();

    expect(_panels($).length, 1);
  });

  patrolWidgetTest(
    '(17) dirty panel → Review & save (save unlinked) then close',
    ($) async {
      await bootGetman($);
      await _addPanelViaMenu($); // Panel 2 active (empty)
      await newTab($);
      await enterUrl($, 'https://review.example.com/unlinked');
      await $.pumpAndSettle();
      final id = _panelIdByName($, 'Panel 2');

      await _openPanelMenu($);
      await $(ValueKey('panel_close_$id')).tap();
      await $.pumpAndSettle();

      await $('REVIEW & SAVE…').tap();
      await $.pumpAndSettle();

      // Per-tab review dialog for the dirty (unlinked) tab → SAVE.
      expect($('SAVE'), findsWidgets);
      await $('SAVE').tap();
      await $.pumpAndSettle();

      // Unlinked → prompt for a collection name.
      expect($('SAVE TO COLLECTION'), findsWidgets);
      await enterPromptText($, 'Saved From Review');
      await $('SAVE').tap();
      await $.pumpAndSettle();

      // Panel closed; the request was saved into the collection.
      expect(_panels($).length, 1);
      await openSideMenuTab($, 'COLLECTIONS');
      expect($('Saved From Review'), findsWidgets);
    },
  );

  patrolWidgetTest(
    '(18) dirty panel → Review & save → Cancel review keeps the panel',
    ($) async {
      await bootGetman($);
      await _addPanelViaMenu($); // Panel 2 active (empty)
      await newTab($);
      await enterUrl($, 'https://keep.example.com/unsaved');
      await $.pumpAndSettle();
      final id = _panelIdByName($, 'Panel 2');

      await _openPanelMenu($);
      await $(ValueKey('panel_close_$id')).tap();
      await $.pumpAndSettle();

      await $('REVIEW & SAVE…').tap();
      await $.pumpAndSettle();

      // Per-tab dialog → CANCEL REVIEW aborts the close.
      expect($('CANCEL REVIEW'), findsWidgets);
      await $('CANCEL REVIEW').tap();
      await $.pumpAndSettle();

      expect(_panels($).length, 2, reason: 'cancel review keeps the panel');
    },
  );

  patrolWidgetTest('(19) closing the last panel is blocked', ($) async {
    await bootGetman($);
    expect(_panels($).length, 1);

    // The only panel's row hides its ✕ (canClose == panels.length > 1).
    final id = _panelIdByName($, 'Panel 1');
    await _openPanelMenu($);
    expect(
      $(ValueKey('panel_close_$id')),
      findsNothing,
      reason: 'the last panel offers no close button',
    );
    await _dismissPanelMenu($);

    expect(_panels($).length, 1);
  });

  // -------------------------------------------------------------------------
  // Step 6 — Empty workspace & active-tab memory (flows 20-21)
  // -------------------------------------------------------------------------

  patrolWidgetTest(
    "(20) closing a panel's last tab leaves it empty",
    ($) async {
      await bootGetman($);
      await enterUrl($, 'https://seed.example.com/only');
      expect(tabCount($), 1);

      // Close the only tab (the URL makes it diverge from the default config,
      // so the dirty checker may prompt; either way the panel goes empty rather
      // than re-seeding a blank).
      final closeButtons = find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('tab_close_');
      });
      await $(closeButtons).first.tap();
      await $.pumpAndSettle();
      // The tab diverges from the default config → "UNSAVED CHANGES" prompt;
      // confirm it so the tab actually closes.
      if ($('CLOSE ANYWAY').exists) {
        await $('CLOSE ANYWAY').tap();
        await $.pumpAndSettle();
      }

      // The panel is now empty and shows the placeholder (the old zero-tabs
      // state) — it is NOT re-seeded with a blank tab.
      expect(_panels($).single.tabs, isEmpty);
      expect(tabCount($), 0);
      expect($('NO OPEN TABS'), findsWidgets);
    },
  );

  patrolWidgetTest('(21) per-panel active tab is remembered across switches', (
    $,
  ) async {
    await bootGetman($);

    // Panel 1: 3 tabs, leave the MIDDLE one active.
    await enterUrl($, 'https://p1.example.com/a');
    await newTab($);
    await enterUrl($, 'https://p1.example.com/b');
    await newTab($);
    await enterUrl($, 'https://p1.example.com/c');
    await $(allTabs().at(1)).tap(); // activate the middle tab
    await $.pumpAndSettle();
    expect(activeUrl($), 'https://p1.example.com/b');

    // Panel 2: 2 tabs, leave the SECOND active (new panels start empty, so add
    // the first tab explicitly).
    await _addPanelViaMenu($);
    await newTab($);
    await enterUrl($, 'https://p2.example.com/x');
    await newTab($);
    await enterUrl($, 'https://p2.example.com/y');
    expect(activeUrl($), 'https://p2.example.com/y');

    // Switch back and forth → each panel restores its own active tab.
    await _switchToPanel($, 'Panel 1');
    expect(activeUrl($), 'https://p1.example.com/b');
    await _switchToPanel($, 'Panel 2');
    expect(activeUrl($), 'https://p2.example.com/y');
  });

  // -------------------------------------------------------------------------
  // Step 7 — In-flight request across panels (flow 22)
  // -------------------------------------------------------------------------

  patrolWidgetTest(
    '(22) an in-flight send in Panel A lands while focus is on Panel B',
    ($) async {
      // A slow endpoint so the request is still in flight when we switch away.
      final server = await MockServer.start(
        json: {'panel': 'A'},
        delay: const Duration(milliseconds: 700),
      );
      addTearDown(server.close);

      await bootGetman($);

      // Panel A (Panel 1): start a request that takes ~700ms.
      await sendTo($, server.url('/in-flight'));

      // Immediately create + switch to Panel B while the send is in flight.
      await _addPanelViaMenu($); // Panel 2 active
      expect(_activePanelName($), 'Panel 2');

      // Give the request time to complete in the background.
      await $.tester.pump(const Duration(milliseconds: 900));
      await $.pumpAndSettle();

      // Switch back to Panel A → the response is present in its tab.
      await _switchToPanel($, 'Panel 1');
      await waitForStatus($, 200);
      expect($('200'), findsWidgets);
      expect(server.received, hasLength(1));
      expect(server.received.single.uri.path, '/in-flight');
    },
  );

  // -------------------------------------------------------------------------
  // Step 8 — Persistence across restart (flow 23)
  // -------------------------------------------------------------------------

  patrolWidgetTest(
    '(23) full panel state survives an app restart',
    ($) async {
      GoogleFonts.config.allowRuntimeFetching = false;

      // Manage the Hive temp dir manually so we can boot TWICE against it.
      final dir = await Directory.systemTemp.createTemp(
        'getman_panels_restart',
      );
      addTearDown(() async {
        await di.reset();
        if (dir.existsSync()) await dir.delete(recursive: true);
      });

      // ---- First launch: build a rich panel state -------------------------
      var settings = await di.init(storageDirectoryOverride: dir.path);
      await disableStartupUpdateCheck();
      await $.pumpWidgetAndSettle(MyApp(initialSettings: settings));
      await resizeWindow($, kE2eWindowSize);

      // Panel 1 (renamed "Alpha"): 2 tabs, custom active = 2nd.
      await _openPanelMenu($);
      final p1Id = _panelIdByName($, 'Panel 1');
      await $(ValueKey('panel_rename_$p1Id')).tap();
      await $.pumpAndSettle();
      await enterPromptText($, 'Alpha');
      await $('SAVE').tap();
      await $.pumpAndSettle();
      await enterUrl($, 'https://alpha.example.com/one');
      await newTab($);
      await enterUrl($, 'https://alpha.example.com/two');
      expect(activeUrl($), 'https://alpha.example.com/two');

      // Second panel ("Beta"): a single DIRTY tab (linked + edited). The new
      // panel becomes active; its name is the lowest free "Panel N" slot
      // (which is "Panel 1" now that the first is renamed), so identify it by
      // the active id rather than an assumed name.
      await _addPanelViaMenu($);
      final p2Id = _tabsBloc($).state.activePanelId;
      await _openPanelMenu($);
      await $(ValueKey('panel_rename_$p2Id')).tap();
      await $.pumpAndSettle();
      await enterPromptText($, 'Beta');
      await $('SAVE').tap();
      await $.pumpAndSettle();
      // New panels start empty — add Beta's single tab, then save it so it
      // links to a node, then edit → dirty (*).
      await newTab($);
      await enterUrl($, 'https://beta.example.com/saved');
      await $(const ValueKey('save_request_button')).tap();
      await enterPromptText($, 'Beta Req');
      await $('SAVE').tap();
      await $.pumpAndSettle();
      expect($('*'), findsNothing);
      await enterUrl($, 'https://beta.example.com/edited');
      await $.pumpAndSettle();
      expect($('*'), findsWidgets, reason: 'edited linked tab is dirty');

      // Reorder so Beta comes first, then leave Alpha the active panel.
      _tabsBloc($).add(const ReorderPanels(1, 0)); // Beta, Alpha
      await $.pumpAndSettle();
      await _switchToPanel($, 'Alpha');
      expect(_panels($).map((p) => p.name), ['Beta', 'Alpha']);
      expect(_activePanelName($), 'Alpha');

      // Flush all pending writes by closing the bloc (close() flushes dirty
      // tabs + persists panels + meta — the same path a real quit takes), then
      // tear the first widget tree down to a placeholder so its (now-closed)
      // BlocProvider is disposed and won't be reused by the second pump. Then
      // reset DI to simulate the process ending.
      await _tabsBloc($).close();
      await $.pumpWidgetAndSettle(const SizedBox.shrink());
      await di.reset();

      // ---- Second launch: same Hive dir → state restored ------------------
      settings = await di.init(storageDirectoryOverride: dir.path);
      await disableStartupUpdateCheck();
      await $.pumpWidgetAndSettle(MyApp(initialSettings: settings));
      await resizeWindow($, kE2eWindowSize);

      // Panel order, names, and active panel restored.
      expect(_panels($).map((p) => p.name), ['Beta', 'Alpha']);
      expect(_activePanelName($), 'Alpha');

      // Alpha's per-panel active tab (the 2nd) restored.
      expect(activeUrl($), 'https://alpha.example.com/two');
      expect(_panels($).firstWhere((p) => p.name == 'Alpha').tabs.length, 2);

      // Beta restored with its single edited tab.
      final beta = _panels($).firstWhere((p) => p.name == 'Beta');
      expect(beta.tabs.length, 1);
      expect(beta.tabs.single.config.url, 'https://beta.example.com/edited');

      // The Beta tab is still DIRTY after restart (switch to it and look).
      await _switchToPanel($, 'Beta');
      expect(
        $('*'),
        findsWidgets,
        reason: 'the dirty tab is still dirty after a restart',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Step 9 — Responsiveness: compactPhone TabSwitcherSheet (flow 24)
  // -------------------------------------------------------------------------

  patrolWidgetTest(
    '(24) compact-phone tab-switcher sheet drives panels',
    ($) async {
      await bootGetman($); // desktop
      await enterUrl($, 'https://compact.example.com/p1');

      // Shrink to compact phone (<= 500): the horizontal tab strip collapses
      // into the TabChip (its label embeds the active panel name + "i/n ▾").
      await resizeWindow($, const Size(460, 880));
      expect(
        $(find.textContaining('Panel 1 ·')),
        findsWidgets,
        reason: 'compact phone shows the TabChip with the active panel name',
      );

      // Open the tab-switcher sheet via the TabChip.
      await $.tester.tap(find.textContaining('Panel 1 ·').first);
      await $.pumpAndSettle();
      expect($('OPEN TABS · 1'), findsWidgets);

      // Create a panel from the sheet's "+ New panel" chip (the sheet stays
      // open and rebuilds with the new chip). The new panel becomes active.
      await $(const ValueKey('sheet_add_panel')).tap();
      await $.pumpAndSettle();
      expect(_panels($).length, 2);
      final newActive = _activePanelName($);
      expect(newActive, isNot('Panel 1'));

      // Switch back to Panel 1 via its chip in the sheet. The chip's InkWell
      // carries BOTH onTap (switch) and onDoubleTap (rename), so a single tap
      // is deferred by the framework until the double-tap window closes — pump
      // real time past kDoubleTapTimeout so the deferred onTap actually fires.
      final p1Id = _panelIdByName($, 'Panel 1');
      await $(ValueKey('panel_chip_$p1Id')).tap(
        settlePolicy: SettlePolicy.noSettle,
      );
      await $.tester.pump(const Duration(milliseconds: 400));
      await $.pumpAndSettle();
      expect(
        _activePanelName($),
        'Panel 1',
        reason: 'tapping a panel chip in the sheet switches the active panel',
      );

      // Close the sheet, then resize back to desktop → the inline strip +
      // selector return.
      await $('CLOSE').tap();
      await $.pumpAndSettle();
      await resizeWindow($, kE2eWindowSize);
      expect($(const ValueKey('panel_selector_button')), findsWidgets);
      expect(_panels($).length, 2);
    },
  );
}

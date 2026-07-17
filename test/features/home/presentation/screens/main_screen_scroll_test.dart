// Tests for the scroll-into-view DEDUP LOGIC in
// `MainScreen._ensureActiveTabVisible` (D7).
//
// Pumping the real MainScreen is infeasible here too — see the header comment
// in main_screen_actions_test.dart for why (GetIt-registered singletons, an
// ambient ticker that never settles under pumpAndSettle). Instead this
// rebuilds the exact same guard clauses in a thin harness with a real
// ScrollController (so `hasClients` is genuinely true), calling them from
// `build()` — the same way `_buildTabBar` calls `_ensureActiveTabVisible`
// inline during a real build, which is what lets the registered
// `addPostFrameCallback` actually fire on the next `pump()` (a frame must
// already be scheduled for that callback to run).
//
// Proves the regression: switching to a panel whose active tab happens to
// sit at the same INDEX as the previous panel's must still attempt to
// scroll — keying the dedup on the active tab's IDENTITY (not the bare
// index) is what makes that true.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verbatim copy of `_MainScreenState._ensureActiveTabVisible`'s guard
/// clauses + scheduling, with the geometry/animateTo body reduced to a
/// counter increment (the fix under test is entirely about WHETHER the body
/// runs, not what it computes once it does).
class _ScrollDedupHarness extends StatefulWidget {
  const _ScrollDedupHarness({
    required this.activeIndex,
    required this.tabIds,
    super.key,
  });

  final int activeIndex;
  final List<String> tabIds;

  @override
  State<_ScrollDedupHarness> createState() => _ScrollDedupHarnessState();
}

class _ScrollDedupHarnessState extends State<_ScrollDedupHarness> {
  final ScrollController controller = ScrollController();
  String? _lastActiveTabId;
  int scrollAttempts = 0;

  void _ensureActiveTabVisible(int activeIndex, List<String> tabIds) {
    if (activeIndex < 0 || activeIndex >= tabIds.length) return;
    final activeTabId = tabIds[activeIndex];
    if (activeTabId == _lastActiveTabId) return;
    _lastActiveTabId = activeTabId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      scrollAttempts++;
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureActiveTabVisible(widget.activeIndex, widget.tabIds);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 200,
        child: ListView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          children: const [SizedBox(width: 2000)],
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'D7: an unchanged index with a DIFFERENT tab id (e.g. after switching '
    "panels) still attempts to scroll — it isn't deduped away",
    (tester) async {
      final key = GlobalKey<_ScrollDedupHarnessState>();

      // Panel A's active tab is at index 0.
      await tester.pumpWidget(
        _ScrollDedupHarness(
          key: key,
          activeIndex: 0,
          tabIds: const [
            'panelA-tab0',
          ],
        ),
      );
      await tester.pump();
      expect(key.currentState!.scrollAttempts, 1);

      // Switch to Panel B: its active tab is ALSO at index 0, but it is a
      // DIFFERENT tab. A bare-index dedup would treat this as "no change" and
      // skip the scroll entirely — the bug this fix addresses.
      await tester.pumpWidget(
        _ScrollDedupHarness(
          key: key,
          activeIndex: 0,
          tabIds: const [
            'panelB-tab0',
          ],
        ),
      );
      await tester.pump();
      expect(
        key.currentState!.scrollAttempts,
        2,
        reason:
            'a different tab at the same index must still trigger a scroll '
            'attempt',
      );
    },
  );

  testWidgets(
    'D7: rebuilding with the SAME tab id at the same index is still deduped '
    '(no redundant scroll)',
    (tester) async {
      final key = GlobalKey<_ScrollDedupHarnessState>();

      await tester.pumpWidget(
        _ScrollDedupHarness(key: key, activeIndex: 0, tabIds: const ['tab0']),
      );
      await tester.pump();
      expect(key.currentState!.scrollAttempts, 1);

      // Rebuild with the exact same active tab — dedup must still apply.
      await tester.pumpWidget(
        _ScrollDedupHarness(key: key, activeIndex: 0, tabIds: const ['tab0']),
      );
      await tester.pump();
      expect(
        key.currentState!.scrollAttempts,
        1,
        reason: 'no change in active tab — the dedup should still apply',
      );
    },
  );
}

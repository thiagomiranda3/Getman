// Tests for TabContentStack use the [childBuilder] injection point rather than
// standing up a full BLoC/provider tree for [RequestView]. This keeps the tests
// fast and self-contained while still exercising all reconciliation, LRU
// eviction, and ExcludeFocus logic (the production [RequestView] path is
// covered by integration/smoke tests elsewhere).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/home/presentation/widgets/tab_content_stack.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

HttpRequestTabEntity _tab(String id) => HttpRequestTabEntity(
  tabId: id,
  config: HttpRequestConfigEntity(id: id),
);

List<HttpRequestTabEntity> _tabs(List<String> ids) => ids.map(_tab).toList();

/// A counter widget whose int state persists across rebuilds as long as the
/// widget's State is alive (same element in the tree).
class _CounterWidget extends StatefulWidget {
  const _CounterWidget({required this.tabId, super.key});
  final String tabId;

  @override
  State<_CounterWidget> createState() => _CounterWidgetState();
}

class _CounterWidgetState extends State<_CounterWidget> {
  int count = 0;

  void increment() => setState(() => count++);

  @override
  Widget build(BuildContext context) {
    return Text('${widget.tabId}:$count');
  }
}

/// A widget that records its own disposal via a callback.
class _DisposeSpy extends StatefulWidget {
  const _DisposeSpy({required this.tabId, required this.onDisposed, super.key});
  final String tabId;
  final VoidCallback onDisposed;

  @override
  State<_DisposeSpy> createState() => _DisposeSpyState();
}

class _DisposeSpyState extends State<_DisposeSpy> {
  @override
  void dispose() {
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('spy:${widget.tabId}');
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Mutable harness that lets us pump [TabContentStack] and change tabs/list.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.initialTabs,
    required this.initialIndex,
    required this.builder,
    super.key,
  });
  final List<HttpRequestTabEntity> initialTabs;
  final int initialIndex;
  final Widget Function(String tabId) builder;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<HttpRequestTabEntity> tabs = widget.initialTabs;
  late int activeIndex = widget.initialIndex;

  void update({List<HttpRequestTabEntity>? newTabs, int? newIndex}) {
    setState(() {
      if (newTabs != null) tabs = newTabs;
      if (newIndex != null) activeIndex = newIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TabContentStack(
      tabs: tabs,
      activeIndex: activeIndex,
      childBuilder: widget.builder,
    );
  }
}

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

Future<_HarnessState> _pumpHarness(
  WidgetTester tester, {
  required List<HttpRequestTabEntity> tabs,
  required int activeIndex,
  required Widget Function(String) builder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _Harness(
          key: const ValueKey('harness'),
          initialTabs: tabs,
          initialIndex: activeIndex,
          builder: builder,
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.state<_HarnessState>(find.byKey(const ValueKey('harness')));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Test 1: Switching away and back preserves child State.
  testWidgets(
    'switching tabs preserves the State of a previously visited tab',
    (tester) async {
      final state = await _pumpHarness(
        tester,
        tabs: _tabs(['a', 'b']),
        activeIndex: 0,
        builder: (id) => _CounterWidget(key: ValueKey('view_$id'), tabId: id),
      );

      // Increment the counter for tab 'a'.
      tester
          .state<_CounterWidgetState>(find.byKey(const ValueKey('view_a')))
          .increment();
      await tester.pump();

      expect(find.text('a:1'), findsOneWidget);

      // Switch to tab 'b'.
      state.update(newIndex: 1);
      await tester.pump();

      // Switch back to tab 'a' — State should still have count==1.
      state.update(newIndex: 0);
      await tester.pump();

      expect(find.text('a:1'), findsOneWidget);
    },
  );

  // Test 2: Visiting 6 tabs evicts the LRU non-active one (5 remain).
  testWidgets('visiting 6 tabs evicts the least-recently-used non-active tab', (
    tester,
  ) async {
    final disposed = <String>{};

    final state = await _pumpHarness(
      tester,
      tabs: _tabs(['a', 'b', 'c', 'd', 'e', 'f']),
      activeIndex: 0,
      builder: (id) => _DisposeSpy(
        key: ValueKey('view_$id'),
        tabId: id,
        onDisposed: () => disposed.add(id),
      ),
    );

    // Visit tabs in order: a(0), b(1), c(2), d(3), e(4) — fills up to 5 slots.
    for (var i = 1; i < 5; i++) {
      state.update(newIndex: i);
      await tester.pump();
    }
    expect(disposed, isEmpty);

    // Now visit tab 'f' (index 5) — should evict 'a' (visited earliest, not
    // active).
    state.update(newIndex: 5);
    await tester.pump();

    expect(disposed, contains('a'));
    expect(disposed.length, 1);

    // Verify exactly 5 spy widgets remain in the tree (including offstage).
    expect(
      find.byType(_DisposeSpy, skipOffstage: false),
      findsNWidgets(kMaxLiveTabViews),
    );
  });

  // Test 3: Closing a tab removes its child from the stack.
  testWidgets('closing a tab removes its child widget from the stack', (
    tester,
  ) async {
    final state = await _pumpHarness(
      tester,
      tabs: _tabs(['x', 'y', 'z']),
      activeIndex: 0,
      builder: (id) => Text('child-$id', key: ValueKey('view_$id')),
    );

    // Visit all three so all three are live.
    state.update(newIndex: 1);
    await tester.pump();
    state.update(newIndex: 2);
    await tester.pump();

    // All three are in the IndexedStack — use skipOffstage: false because
    // IndexedStack hides non-active children via Offstage.
    expect(find.text('child-x', skipOffstage: false), findsOneWidget);
    expect(find.text('child-y', skipOffstage: false), findsOneWidget);
    expect(find.text('child-z', skipOffstage: false), findsOneWidget);

    // Remove tab 'y' and activate 'z' (now at index 1).
    state.update(newTabs: _tabs(['x', 'z']), newIndex: 1);
    await tester.pump();

    expect(find.text('child-y', skipOffstage: false), findsNothing);
    // 'x' is live but offstage; 'z' is the active (onstage) child.
    expect(find.text('child-x', skipOffstage: false), findsOneWidget);
    expect(find.text('child-z'), findsOneWidget);
  });

  // Test 4: ExcludeFocus — only the active child has excluding==false.
  testWidgets('only the active child has ExcludeFocus.excluding set to false', (
    tester,
  ) async {
    final state = await _pumpHarness(
      tester,
      tabs: _tabs(['p', 'q', 'r']),
      activeIndex: 0,
      builder: (id) => Text('child-$id', key: ValueKey('view_$id')),
    );

    // Visit all three to get all three live.
    state.update(newIndex: 1);
    await tester.pump();
    state.update(newIndex: 2);
    await tester.pump();

    // Active is index 2 → id 'r'. Verify the ExcludeFocus widgets.
    // Use skipOffstage: false because non-active children are wrapped in
    // Offstage.
    final excludeFocusWidgets = tester
        .widgetList<ExcludeFocus>(
          find.byType(ExcludeFocus, skipOffstage: false),
        )
        .toList();
    // Three live tabs means three ExcludeFocus nodes.
    expect(excludeFocusWidgets.length, 3);

    // Exactly one should have excluding==false (the active tab 'r').
    final included = excludeFocusWidgets.where((e) => !e.excluding).toList();
    expect(included.length, 1);

    // The non-excluding one should be inside the Offstage keyed to 'r'.
    final activeExclude = find.descendant(
      of: find.byKey(const ValueKey('offstage_r')),
      matching: find.byType(ExcludeFocus, skipOffstage: false),
    );
    expect(tester.widget<ExcludeFocus>(activeExclude).excluding, isFalse);
  });

  // Test 5: Empty tabs list returns SizedBox.shrink without crashing.
  testWidgets('empty tab list renders SizedBox.shrink without error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabContentStack(
            tabs: const [],
            activeIndex: 0,
            childBuilder: (id) => Text('child-$id'),
          ),
        ),
      ),
    );

    expect(find.byType(SizedBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

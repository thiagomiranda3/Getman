import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

void main() {
  testWidgets('default AppMotion hooks are identity (return child unchanged)', (
    tester,
  ) async {
    const m = AppMotion();
    const marker = SizedBox(key: ValueKey('m'));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      identical(m.treeDragFeedback(ctx, child: marker), marker),
      isTrue,
    );
    expect(
      identical(m.treeDropHighlight(ctx, child: marker, active: true), marker),
      isTrue,
    );
    expect(
      identical(
        m.treeExpandFlourish(ctx, child: marker, expanded: true),
        marker,
      ),
      isTrue,
    );
  });

  test('copyWith overrides only the supplied hooks', () {
    Widget custom(
      BuildContext c, {
      required Widget child,
    }) => const SizedBox(key: ValueKey('custom'));
    const base = AppMotion();
    final copy = base.copyWith(treeDragFeedback: custom);
    expect(identical(copy.treeDragFeedback, custom), isTrue);
    expect(
      identical(copy.treeExpandFlourish, base.treeExpandFlourish),
      isTrue,
    );
    expect(identical(copy.treeDropHighlight, base.treeDropHighlight), isTrue);
  });
}

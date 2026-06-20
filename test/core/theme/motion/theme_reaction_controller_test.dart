import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

void main() {
  test('fire updates latest, bumps seq, and notifies', () {
    final c = ThemeReactionController();
    var notifications = 0;
    c.addListener(() => notifications++);

    expect(c.latest, isNull);
    expect(c.seq, 0);

    c.fire(
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    );
    expect(c.latest!.kind, ThemeReactionKind.success);
    expect(c.seq, 1);
    expect(notifications, 1);

    // Identical reaction still bumps seq + notifies (re-trigger).
    c.fire(
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    );
    expect(c.seq, 2);
    expect(notifications, 2);

    c.dispose();
  });
}

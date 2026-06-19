import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

void main() {
  group('TabsState reaction signal', () {
    test('defaults: no reaction, seq 0', () {
      const s = TabsState();
      expect(s.lastReaction, isNull);
      expect(s.reactionSeq, 0);
    });

    test('copyWith sets reaction + seq and keeps them in equality', () {
      const base = TabsState();
      final next = base.copyWith(
        lastReaction: const ThemeReaction(
          kind: ThemeReactionKind.success,
          statusCode: 200,
        ),
        reactionSeq: 1,
      );
      expect(next.reactionSeq, 1);
      expect(next.lastReaction!.kind, ThemeReactionKind.success);
      expect(next, isNot(equals(base)));
    });
  });
}

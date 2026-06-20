import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/audio/theme_sound_service_stub.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

void main() {
  test('stub play never throws and is a no-op', () async {
    final ThemeSoundService svc = StubThemeSoundService();
    await svc.play(
      'rpg',
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    );
    svc.dispose();
  });
}

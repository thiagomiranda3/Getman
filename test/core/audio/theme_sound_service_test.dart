import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/audio/theme_sound_service_audioplayers.dart';

void main() {
  // Regression guard: web must NOT fall back to a silent no-op. `audioplayers`
  // is cross-platform (audioplayers_web ships the web backend), so every
  // platform — web included — gets the real audioplayers-backed service.
  test('factory returns the audioplayers-backed service (never a no-op)', () {
    expect(createThemeSoundService(), isA<AudioPlayersThemeSoundService>());
  });

  test('cancelled reaction plays no cue and never throws', () async {
    final ThemeSoundService svc = AudioPlayersThemeSoundService();
    await svc.play(
      'rpg',
      const ThemeReaction(kind: ThemeReactionKind.cancelled),
    );
    svc.dispose();
  });
}

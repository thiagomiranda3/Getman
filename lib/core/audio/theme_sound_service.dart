import 'package:getman/core/audio/theme_sound_service_audioplayers.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// Plays short, themed one-shot sound effects keyed by (themeId, reaction).
/// Implementations must NEVER throw from [play] — a missing asset or
/// unavailable audio backend degrades to silence.
abstract class ThemeSoundService {
  Future<void> play(String themeId, ThemeReaction reaction);
  void dispose();
}

/// audioplayers-backed on every platform — `audioplayers` ships a web backend
/// (`audioplayers_web`), so there is no web no-op stub. Failures (missing
/// asset, no backend, blocked autoplay) degrade to silence inside the service.
ThemeSoundService createThemeSoundService() => createThemeSoundServiceImpl();

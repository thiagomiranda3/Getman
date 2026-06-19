import 'package:getman/core/audio/theme_sound_service_stub.dart'
    if (dart.library.io) 'package:getman/core/audio/theme_sound_service_io.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// Plays short, themed one-shot sound effects keyed by (themeId, reaction).
/// Implementations must NEVER throw from [play] — a missing asset or
/// unavailable audio backend degrades to silence.
abstract class ThemeSoundService {
  Future<void> play(String themeId, ThemeReaction reaction);
  void dispose();
}

/// Native => audioplayers-backed; web/unsupported => no-op stub.
ThemeSoundService createThemeSoundService() => createThemeSoundServiceImpl();

import 'package:getman/core/audio/theme_sound_service_audioplayers.dart';

/// What happened to a request, in sound-cue terms. A small value type local to
/// the audio subsystem: the motion-spine `ThemeReaction` that used to carry
/// this was removed with the status-code reactions, but the audio cue map still
/// keys off the same outcome kinds. (The whole audio subsystem is slated for
/// removal in a follow-up.)
enum ThemeReactionKind {
  sendStarted,
  success,
  clientError,
  serverError,
  networkError,
  cancelled,
}

/// The outcome a sound cue is played for.
class ThemeReaction {
  const ThemeReaction({required this.kind});
  final ThemeReactionKind kind;
}

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

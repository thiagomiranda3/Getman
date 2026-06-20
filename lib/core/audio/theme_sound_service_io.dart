import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// audioplayers-backed sound service for native platforms.
///
/// Defensive: the [AudioPlayer] is constructed lazily on the first [play] call
/// so no platform channel is touched at construction time (safe in headless
/// tests, CI, and platforms without an audio backend). Any failure — missing
/// asset, no GStreamer on Linux, headless environment — is caught and logged so
/// audio never crashes the app.
class IoThemeSoundService implements ThemeSoundService {
  AudioPlayer? _player;

  /// Maps a reaction to the cue file name (without extension), or null when no
  /// cue should be played for that kind.
  static String? _cue(ThemeReaction r) {
    switch (r.kind) {
      case ThemeReactionKind.sendStarted:
        return 'send';
      case ThemeReactionKind.success:
        return 'success';
      case ThemeReactionKind.clientError:
      case ThemeReactionKind.serverError:
      case ThemeReactionKind.networkError:
        return 'error';
      case ThemeReactionKind.cancelled:
        return null;
    }
  }

  @override
  Future<void> play(String themeId, ThemeReaction reaction) async {
    final cue = _cue(reaction);
    if (cue == null) return;
    try {
      if (_player == null) {
        _player = AudioPlayer(playerId: 'getman_theme_sfx');
        await _player!.setReleaseMode(ReleaseMode.stop);
      }
      await _player!.stop();
      await _player!.play(
        AssetSource('sounds/$themeId/$cue.mp3'),
        volume: 0.5,
      );
    } on Object catch (e) {
      // Missing asset / unsupported backend → degrade to silence.
      debugPrint('ThemeSoundService: play failed ($themeId/$cue): $e');
    }
  }

  @override
  void dispose() {
    try {
      unawaited(_player?.dispose());
    } on Object catch (e) {
      debugPrint('ThemeSoundService: dispose failed: $e');
    }
    _player = null;
  }
}

ThemeSoundService createThemeSoundServiceImpl() => IoThemeSoundService();

import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// No-op implementation used on web and as the fallback.
class StubThemeSoundService implements ThemeSoundService {
  @override
  Future<void> play(String themeId, ThemeReaction reaction) async {}

  @override
  void dispose() {}
}

ThemeSoundService createThemeSoundServiceImpl() => StubThemeSoundService();

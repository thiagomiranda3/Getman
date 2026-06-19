import 'package:flutter/foundation.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// App-wide bus for request-driven theme reactions. Reactions are pushed in
/// via [fire]; theme overlay widgets subscribe and play effects. Registered as
/// a DI singleton and exposed to the widget tree via a provider.
class ThemeReactionController extends ChangeNotifier {
  ThemeReaction? _latest;
  int _seq = 0;

  ThemeReaction? get latest => _latest;

  /// Monotonic; bumped on every [fire] (even for identical reactions) so an
  /// overlay can re-run an effect for two successive identical responses.
  int get seq => _seq;

  void fire(ThemeReaction reaction) {
    _latest = reaction;
    _seq++;
    notifyListeners();
  }
}

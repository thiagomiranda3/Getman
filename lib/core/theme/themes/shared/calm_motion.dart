// Identity AppMotion factory shared by every "calm" theme (Classic, Dracula,
// Editorial) that ships no event-driven collections-tree drag/drop/expand
// juice — always returns const AppMotion() regardless of reduceEffects.

import 'package:getman/core/theme/extensions/app_motion.dart';

/// Calm themes ship no event-driven motion.
AppMotion calmMotion({required bool reduceEffects}) => const AppMotion();

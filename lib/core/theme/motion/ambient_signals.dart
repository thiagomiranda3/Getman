import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset;
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

/// The shared input bundle threaded into a theme's ambient `scaffoldBackground`
/// painter (VM-C1 + VM-C2). Plumbed ONCE per painter; C1 (pointer) and
/// C2 (pulse) are just fields read off it. Built only in animated mode — the
/// reduced-effects static variant passes `null` so nothing subscribes.
@immutable
class AmbientSignals {
  const AmbientSignals({
    required this.pointer,
    required this.pulse,
    required this.isDark,
  });

  /// Normalized pointer position (theme-specific convention: rpg uses -1..1
  /// from centre, glass uses 0..1). Widget keeps its convention.
  final ValueListenable<Offset> pointer;

  /// Session rhythm (activityLevel / idleFactor). Also a `Listenable`, so merge
  /// it into the painter's `repaint:`.
  final WorkspacePulseController pulse;

  final bool isDark;
}

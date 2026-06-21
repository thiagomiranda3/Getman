import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset;
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

/// A transient pointer-click ripple seed (VM-C1). [position] is normalized
/// (0..1) over the ambient surface; [bornAtMs] is the widget-owned monotonic
/// timestamp the painter uses to age the ripple out (self-disposing).
@immutable
class AmbientImpulse {
  const AmbientImpulse({required this.position, required this.bornAtMs});

  final Offset position;
  final int bornAtMs;

  @override
  bool operator ==(Object other) =>
      other is AmbientImpulse &&
      other.position == position &&
      other.bornAtMs == bornAtMs;

  @override
  int get hashCode => Object.hash(position, bornAtMs);
}

/// The shared input bundle threaded into a theme's ambient `scaffoldBackground`
/// painter (VM-C1 + VM-C2). Plumbed ONCE per painter; C1 (pointer/impulses) and
/// C2 (pulse) are just fields read off it. Built only in animated mode — the
/// reduced-effects static variant passes `null` so nothing subscribes.
@immutable
class AmbientSignals {
  const AmbientSignals({
    required this.pointer,
    required this.impulses,
    required this.pulse,
    required this.isDark,
  });

  /// Normalized pointer position (theme-specific convention: rpg uses -1..1
  /// from centre, glass uses 0..1). Widget keeps its convention.
  final ValueListenable<Offset> pointer;

  /// Active click ripples; the owning widget drops aged entries.
  final ValueListenable<List<AmbientImpulse>> impulses;

  /// Session rhythm (activityLevel / idleFactor). Also a `Listenable`, so merge
  /// it into the painter's `repaint:`.
  final WorkspacePulseController pulse;

  final bool isDark;
}

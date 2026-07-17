// WorkspacePulseController: app-wide idle/presence rhythm signal for
// ambient backgrounds. idleFactor ramps 0 (active) -> 1 (fully idle) via a
// 1s timer that only runs while something is listening (started in
// addListener, cancelled when the last listener leaves), so it never wakes
// the app when no animated ambient is mounted (reduceEffects or a calm
// theme). touch() resets idle on user interaction.
import 'dart:async';

import 'package:flutter/foundation.dart';

/// App-wide idle/presence rhythm signal for ambient backgrounds.
///
/// Tracks how long the workspace has been quiet ([idleFactor]: 0 = active,
/// 1 = fully idle) so ambient painters can dim/slow during inactivity.
/// A low-frequency timer drives the idle ramp; it only runs while something
/// is listening (started in [addListener], cancelled when the last listener
/// leaves), so it never wakes the app when no animated ambient is mounted
/// (e.g. reduceEffects or a calm theme).
class WorkspacePulseController extends ChangeNotifier {
  WorkspacePulseController({
    this._tickInterval = const Duration(seconds: 1),
  });

  final Duration _tickInterval;
  Timer? _timer;

  // 0..1 idle ramp; rises one step per tick, resets on touch.
  double _idle = 0;

  static const double _idleStep = 1 / 30; // ~30 ticks (≈30s) to fully idle

  double get idleFactor => _idle;

  /// Whether any listener is currently subscribed. Exposed for tests that need
  /// to verify ambient painters subscribe (and unsubscribe) to the controller.
  @visibleForTesting
  bool get debugHasListeners => hasListeners;

  /// User interacted (pointer/click) — clear idle.
  void touch() {
    if (_idle == 0) return;
    _idle = 0;
    notifyListeners();
  }

  /// One idle step. Driven by the internal timer; exposed for tests.
  @visibleForTesting
  void tick() {
    final beforeIdle = _idle;
    _idle = (_idle + _idleStep).clamp(0.0, 1.0);
    if (_idle != beforeIdle) notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _timer ??= Timer.periodic(_tickInterval, (_) => tick());
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

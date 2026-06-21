import 'dart:async';

import 'package:flutter/foundation.dart';

/// App-wide "session rhythm" signal for VM-C2: ambient backgrounds read it to
/// intensify on a burst of sends ([activityLevel]) and to calm down after
/// inactivity ([idleFactor]).
///
/// Logic lives here (unit-tested in isolation) so the painters stay logic-free
/// and just read two doubles. A low-frequency timer drives decay/idle; it only
/// runs while something is listening (started in [addListener], cancelled when
/// the last listener leaves), so it never wakes the app when no animated
/// ambient is mounted (e.g. reduceEffects or a calm theme).
class WorkspacePulseController extends ChangeNotifier {
  WorkspacePulseController({
    Duration tickInterval = const Duration(seconds: 1),
  }) : _tickInterval = tickInterval;

  final Duration _tickInterval;
  Timer? _timer;

  // 0..1 recent-send intensity; multiplicative decay per tick.
  double _activity = 0;
  // 0..1 idle ramp; rises one step per tick, resets on activity/touch.
  double _idle = 0;

  static const double _bumpAmount = 0.34; // each send
  static const double _decayPerTick = 0.85; // ~6 ticks to near-zero
  static const double _idleStep = 1 / 30; // ~30 ticks (≈30s) to fully idle

  double get activityLevel => _activity;
  double get idleFactor => _idle;

  /// Whether any listener is currently subscribed. Exposed for tests that need
  /// to verify ambient painters subscribe (and unsubscribe) to the controller.
  @visibleForTesting
  bool get debugHasListeners => hasListeners;

  /// A request reaction happened — intensify and clear idle.
  void bump() {
    _activity = (_activity + _bumpAmount).clamp(0.0, 1.0);
    _idle = 0;
    notifyListeners();
  }

  /// User interacted (pointer/click) — clear idle only.
  void touch() {
    if (_idle == 0) return;
    _idle = 0;
    notifyListeners();
  }

  /// One decay/idle step. Driven by the internal timer; exposed for tests.
  @visibleForTesting
  void tick() {
    final before = _activity;
    final beforeIdle = _idle;
    _activity *= _decayPerTick;
    if (_activity < 0.01) _activity = 0;
    _idle = (_idle + _idleStep).clamp(0.0, 1.0);
    if (_activity != before || _idle != beforeIdle) notifyListeners();
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

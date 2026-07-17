// Collapses a burst of calls into one deferred action fired after a quiet
// period; keeps per-keystroke work (search filtering, tree rebuilds) off the
// typing hot path. Owners must call dispose() to cancel a pending timer.

import 'dart:async';

/// Collapses a burst of calls into a single deferred action: each [run] cancels
/// the previous pending timer and reschedules, so the action fires only once
/// the caller stops invoking for [duration]. Used to keep per-keystroke work
/// (search filtering, tree rebuilds) off the typing hot path.
///
/// Owners must call [dispose] to cancel any pending action when torn down.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 220)});

  final Duration duration;
  Timer? _timer;

  /// (Re)schedules [action] after [duration], cancelling any pending one.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Cancels a pending action without running it.
  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}

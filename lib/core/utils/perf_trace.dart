// dart:developer Timeline wrappers (traceSync/traceAsync) for profile-mode
// instrumentation; no-ops in release builds, so safe to leave on hot paths.
// View spans in DevTools -> Performance under `fvm flutter run --profile`.

import 'dart:developer' as developer;

/// Thin wrappers over `dart:developer` [developer.Timeline] for profile-mode
/// instrumentation. In release builds Timeline calls are no-ops, so these are
/// safe to leave on the hot path. View the events in DevTools → Performance
/// when running `fvm flutter run --profile` (see docs/PERFORMANCE.md).
///
/// Use [traceSync] around synchronous CPU work and [traceAsync] around an
/// awaited span (e.g. the send → response → rules → persist pipeline).
T traceSync<T>(String name, T Function() body) =>
    developer.Timeline.timeSync(name, body);

Future<T> traceAsync<T>(String name, Future<T> Function() body) async {
  final task = developer.TimelineTask()..start(name);
  try {
    return await body();
  } finally {
    task.finish();
  }
}

import 'package:hive_ce/hive.dart';

/// Replaces the contents of [box] with [items] (clear + addAll).
///
/// Hive has no real transaction, so this can't be truly atomic. It does two
/// things to avoid silent data loss:
///  - materializes [items] *before* clearing, so passing a lazy iterable
///    derived from `box.values` can't empty itself mid-operation;
///  - on an addAll failure (e.g. disk full / serialization error), makes a
///    best-effort restore of the previous contents instead of leaving the box
///    empty, then rethrows the original error.
Future<void> replaceAllInBox<T>(Box<T> box, Iterable<T> items) async {
  final materialized = items.toList(growable: false);
  final snapshot = box.values.toList(growable: false);
  await box.clear();
  try {
    await box.addAll(materialized);
  } on Object catch (_) {
    try {
      await box.clear();
      await box.addAll(snapshot);
    } on Object catch (_) {
      // Nothing more we can safely do; surface the original failure below.
    }
    rethrow;
  }
}

// Generic Hive box helper: replaceAllKeyedInBox swaps a box's contents to a
// keyed snapshot WITHOUT clear() — putAll the new entries, then delete the
// stale keys — so a crash/failure mid-replace can leave extras behind but can
// never wipe the box.

import 'package:hive_ce/hive.dart';

/// Replaces the contents of [box] with [entries]: keyed upsert + stale-key
/// delete — never `clear()`.
///
/// Hive has no real transaction, so a clear()-then-write replace has a window
/// where a crash (or a failed write) leaves the box EMPTY — silent total data
/// loss (H2b). This helper orders the phases so the previous data survives
/// every failure point:
///  1. snapshot the keys absent from [entries] (stale);
///  2. `putAll(entries)` — overwrites surviving keys, adds new ones;
///  3. `deleteAll(stale keys)`.
/// A failure in (2) leaves the previous entries intact (some may already
/// carry their new value — still valid data, never a wipe); a failure in (3)
/// leaves stale extras that the next successful replace removes.
///
/// [entries] values must not be `HiveObject` instances currently stored in
/// [box] under a DIFFERENT key (Hive forbids one instance under two keys) —
/// pass fresh/detached instances.
Future<void> replaceAllKeyedInBox<K, T>(Box<T> box, Map<K, T> entries) async {
  final staleKeys = box.keys
      .where((k) => !entries.containsKey(k))
      .toList(growable: false);
  await box.putAll(entries);
  await box.deleteAll(staleKeys);
}

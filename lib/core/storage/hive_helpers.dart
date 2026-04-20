import 'package:hive/hive.dart';

/// Atomically replaces the contents of [box] with [items] (clear + addAll).
/// Hive does not expose a true transaction, so this is the idiomatic
/// "replace all" pattern we use across data sources.
Future<void> replaceAllInBox<T>(Box<T> box, Iterable<T> items) async {
  await box.clear();
  await box.addAll(items);
}

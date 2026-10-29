// Hive primitive-int persistence for locally learned JSON field names.
// No adapter/typeId: each key is a name and its value is the usage count.
// Writes serialize across editors, retain the 2,000 most-used names (lexical
// ties), reject empty/over-255-UTF-8-byte names and cap counts at one billion.
// Failed writes leave the last successful snapshot available and do not poison
// the queue; request values are never accepted or persisted by this API.
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/logic/body_field_dictionary_limits.dart';
import 'package:getman/features/tabs/domain/repositories/body_field_dictionary_repository.dart';
import 'package:hive_ce/hive.dart';

class BodyFieldDictionaryRepositoryImpl
    implements BodyFieldDictionaryRepository {
  BodyFieldDictionaryRepositoryImpl(this._box) {
    _counts = {
      for (final entry in _box.toMap().entries)
        if (entry.key is String &&
            isLearnableBodyFieldName(entry.key as String) &&
            entry.value > 0)
          entry.key as String: entry.value.clamp(1, _maxCount),
    };
    _entries = _rank(_counts);
    _counts = {for (final entry in _entries) entry.name: entry.usageCount};
  }

  static const _maxEntries = 2000;
  static const _maxCount = 1000000000;

  final Box<int> _box;
  late Map<String, int> _counts;
  late List<BodyFieldEntry> _entries;
  Future<void> _pending = Future.value();

  @override
  List<BodyFieldEntry> get entries => _entries;

  @override
  Future<void> recordUsage(Map<String, int> increments) {
    final snapshot = Map<String, int>.of(increments);
    final operation = _pending.then((_) => _record(snapshot));
    // Attach recovery immediately, while returning the original failure to
    // its caller. Subsequent edits must still be able to save after an error.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  Future<void> _record(Map<String, int> increments) async {
    final next = Map<String, int>.of(_counts);
    var changed = false;
    for (final entry in increments.entries) {
      if (!isLearnableBodyFieldName(entry.key) || entry.value <= 0) continue;
      final previous = next[entry.key] ?? 0;
      final count = (previous + entry.value.clamp(1, _maxCount)).clamp(
        1,
        _maxCount,
      );
      if (count == previous) continue;
      next[entry.key] = count;
      changed = true;
    }
    if (!changed) return;
    final ranked = _rank(next);
    final retained = {
      for (final entry in ranked) entry.name: entry.usageCount,
    };
    try {
      await _box.putAll(retained);
      final removed = _box.keys
          .where((key) => !retained.containsKey(key))
          .toList();
      if (removed.isNotEmpty) await _box.deleteAll(removed);
      _counts = retained;
      _entries = ranked;
    } on Object catch (error) {
      throw PersistenceFailure('Could not save JSON field dictionary: $error');
    }
  }

  static List<BodyFieldEntry> _rank(Map<String, int> counts) {
    final entries =
        [
          for (final entry in counts.entries)
            BodyFieldEntry(name: entry.key, usageCount: entry.value),
        ]..sort((a, b) {
          final frequency = b.usageCount.compareTo(a.usageCount);
          return frequency != 0 ? frequency : a.name.compareTo(b.name);
        });
    return List.unmodifiable(entries.take(_maxEntries));
  }
}

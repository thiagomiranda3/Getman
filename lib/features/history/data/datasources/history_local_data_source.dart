import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

abstract class HistoryLocalDataSource {
  Future<List<HttpRequestConfig>> getHistory();
  Future<void> addToHistory(HttpRequestConfig config, int limit);
  Stream<void> watch();
}

class HistoryLocalDataSourceImpl implements HistoryLocalDataSource {
  Box<HttpRequestConfig> _box() =>
      Hive.box<HttpRequestConfig>(HiveBoxes.history);

  // Signature index: hashCode(method+url+body) → list of box keys with that
  // hash. Built lazily on first addToHistory call; rebuilt if box length drifts
  // (e.g. external deletes or box replacements between sessions).
  Map<int, List<dynamic>>? _signatureIndex;
  int _indexedKeyCount = 0;

  void _buildIndex(Box<HttpRequestConfig> box) {
    _signatureIndex = {};
    _indexedKeyCount = 0;
    for (final entry in box.toMap().entries) {
      final hash = entry.value.hashCode;
      (_signatureIndex![hash] ??= []).add(entry.key);
      _indexedKeyCount++;
    }
  }

  void _ensureIndex(Box<HttpRequestConfig> box) {
    if (_signatureIndex == null) {
      _buildIndex(box);
      return;
    }
    // Defensive resync: if something mutated the box outside our tracking,
    // rebuild.
    if (_indexedKeyCount != box.length) {
      _buildIndex(box);
    }
  }

  void _indexRemoveKey(int hash, dynamic key) {
    final keys = _signatureIndex?[hash];
    if (keys == null) return;
    keys.remove(key);
    if (keys.isEmpty) _signatureIndex!.remove(hash);
    _indexedKeyCount--;
  }

  void _indexAddKey(int hash, dynamic key) {
    (_signatureIndex![hash] ??= []).add(key);
    _indexedKeyCount++;
  }

  @override
  Future<List<HttpRequestConfig>> getHistory() async {
    try {
      return _box().values.toList();
    } catch (e) {
      throw PersistenceException('Failed to read history', cause: e);
    }
  }

  @override
  Future<void> addToHistory(HttpRequestConfig config, int limit) async {
    try {
      final box = _box();
      _ensureIndex(box);

      // Dedup: look up by signature hash, then confirm equality
      // (hash-collision guard).
      final candidates = List<dynamic>.from(
        _signatureIndex![config.hashCode] ?? const [],
      );
      for (final key in candidates) {
        final existing = box.get(key);
        if (existing != null && existing == config) {
          await box.delete(key);
          _indexRemoveKey(config.hashCode, key);
          break; // at most one duplicate by contract
        }
      }

      // Append newest entry.
      final newKey = await box.add(config);
      _indexAddKey(config.hashCode, newKey);

      // Trim: drop the oldest (lowest-index) entries in ONE batched delete so
      // a single watch event fires instead of one per removal.
      if (box.length > limit) {
        final removeCount = box.length - limit;
        final keysToRemove = <dynamic>[];
        // Advance past any null key instead of consuming a removal slot for
        // it, so exactly `removeCount` real entries are dropped and the box
        // can't be left above the limit.
        var i = 0;
        while (keysToRemove.length < removeCount && i < box.length) {
          final oldKey = box.keyAt(i);
          final oldest = box.getAt(i);
          i++;
          if (oldKey == null) continue;
          keysToRemove.add(oldKey);
          if (oldest != null) _indexRemoveKey(oldest.hashCode, oldKey);
        }
        await box.deleteAll(keysToRemove);
      }
    } catch (e) {
      throw PersistenceException('Failed to add to history', cause: e);
    }
  }

  @override
  Stream<void> watch() => _box().watch().map((_) {});
}

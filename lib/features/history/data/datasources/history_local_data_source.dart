// History writes: appends happen via SendRequestUseCase; since D3 the UI can
// also delete one entry, clear all, and restore deleted snapshots (undo,
// signature-duplicates skipped). Dedup is by request signature
// (HttpRequestConfig's method+url+body plus
// bodyType/graphqlVariables/bodyFilePath/formFields); header differences do
// NOT dedupe. addToHistory maintains an in-memory hashCode->keys index
// (rebuilt if the box length drifts) so dedup lookup is O(1) instead of a
// full box scan. Trim uses a `while` loop so lowering the history limit
// actually shrinks the box. watch() exposes Box.watch(); the repository
// reverses insertion order so callers get newest-first.

import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

abstract class HistoryLocalDataSource {
  Future<List<HttpRequestConfig>> getHistory();
  Future<void> addToHistory(HttpRequestConfig config, int limit);

  /// Deletes the record whose model `id` equals [id]. No-op if absent.
  ///
  /// `id` is unique across the box: every stored row is minted a fresh id
  /// at write time by `HistoryRepositoryImpl.addToHistory` (never the
  /// source entity's id — a resent tab would otherwise share its id across
  /// every row), so at most one record can ever match. restoreToHistory is
  /// the one path that reinstates a caller-supplied id verbatim (an UNDO
  /// must reinsert the exact deleted record).
  Future<void> deleteFromHistory(String id);

  /// Removes every record.
  Future<void> clearHistory();

  /// Re-inserts previously deleted records (an UNDO). Any config whose
  /// request signature already exists in the box is skipped — the live
  /// entry is newer than the undo snapshot.
  Future<void> restoreToHistory(List<HttpRequestConfig> configs);

  Stream<void> watch();
}

class HistoryLocalDataSourceImpl implements HistoryLocalDataSource {
  Box<HttpRequestConfig> _box() =>
      Hive.box<HttpRequestConfig>(HiveBoxes.history);

  // Signature index: HttpRequestConfig.hashCode (the full request signature —
  // method/url/body plus bodyType/graphqlVariables/bodyFilePath/formFields) →
  // list of box keys with that hash. Built lazily on first addToHistory call;
  // rebuilt if box length drifts (e.g. external deletes or box replacements
  // between sessions).
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
  Future<void> deleteFromHistory(String id) async {
    try {
      final box = _box();
      for (final entry in box.toMap().entries) {
        if (entry.value.id == id) {
          // Keep the lazily-built signature index consistent; if it hasn't
          // been built yet there is nothing to maintain (it rebuilds from
          // the box on first use).
          if (_signatureIndex != null) {
            _indexRemoveKey(entry.value.hashCode, entry.key);
          }
          await box.delete(entry.key);
          return;
        }
      }
    } catch (e) {
      throw PersistenceException('Failed to delete history entry', cause: e);
    }
  }

  @override
  Future<void> clearHistory() async {
    try {
      await _box().clear();
      // Drop the index wholesale; it rebuilds lazily on the next add.
      _signatureIndex = null;
      _indexedKeyCount = 0;
    } catch (e) {
      throw PersistenceException('Failed to clear history', cause: e);
    }
  }

  @override
  Future<void> restoreToHistory(List<HttpRequestConfig> configs) async {
    try {
      final box = _box();
      _ensureIndex(box);
      for (final config in configs) {
        // Signature-duplicate guard (same hash-then-equality pattern as
        // addToHistory's dedup): if the user re-sent the request after
        // deleting it, UNDO must not create a second copy.
        final candidates = _signatureIndex![config.hashCode] ?? const [];
        final duplicate = candidates.any((key) {
          final existing = box.get(key);
          return existing != null && existing == config;
        });
        if (duplicate) continue;
        final key = await box.add(config);
        _indexAddKey(config.hashCode, key);
      }
    } catch (e) {
      throw PersistenceException(
        'Failed to restore history entries',
        cause: e,
      );
    }
  }

  @override
  Stream<void> watch() => _box().watch().map((_) {});
}

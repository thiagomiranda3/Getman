// Hive-backed persistence for per-request chaining rules (box:
// 'requestRules', keyed by config id). Wraps RequestRulesModel get/save/
// delete plus the boot-time sweepOrphans housekeeping (H4); consumed by
// RequestRulesRepositoryImpl and the DI init sweep.

import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

abstract class RequestRulesLocalDataSource {
  RequestRulesModel? getRules(String configId);
  Future<void> saveRules(RequestRulesModel rules);
  Future<void> deleteRules(String configId);

  /// Deletes every stored rules entry whose key (config id) is NOT in
  /// [liveConfigIds]; returns how many entries were removed. Boot-time
  /// housekeeping (H4): rules are keyed by config id (UUIDs, never reused)
  /// and nothing deletes them when their owner disappears — without this the
  /// box grows forever. The live-owner set is derived in DI init (see
  /// `_sweepOrphanedRequestRules` in injection_container.dart).
  Future<int> sweepOrphans(Set<String> liveConfigIds);
}

class RequestRulesLocalDataSourceImpl implements RequestRulesLocalDataSource {
  Box<RequestRulesModel> _box() =>
      Hive.box<RequestRulesModel>(HiveBoxes.requestRules);

  @override
  RequestRulesModel? getRules(String configId) {
    try {
      return _box().get(configId);
    } catch (e) {
      throw PersistenceException('Failed to read request rules', cause: e);
    }
  }

  @override
  Future<void> saveRules(RequestRulesModel rules) async {
    try {
      await _box().put(rules.configId, rules);
    } catch (e) {
      throw PersistenceException('Failed to save request rules', cause: e);
    }
  }

  @override
  Future<void> deleteRules(String configId) async {
    try {
      await _box().delete(configId);
    } catch (e) {
      throw PersistenceException('Failed to delete request rules', cause: e);
    }
  }

  @override
  Future<int> sweepOrphans(Set<String> liveConfigIds) async {
    try {
      final box = _box();
      final staleKeys = box.keys
          .where((k) => !liveConfigIds.contains(k))
          .toList(growable: false);
      await box.deleteAll(staleKeys);
      return staleKeys.length;
    } catch (e) {
      throw PersistenceException(
        'Failed to sweep orphaned request rules',
        cause: e,
      );
    }
  }
}

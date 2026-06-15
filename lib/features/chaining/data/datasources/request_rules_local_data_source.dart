import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

abstract class RequestRulesLocalDataSource {
  RequestRulesModel? getRules(String configId);
  Future<void> saveRules(RequestRulesModel rules);
  Future<void> deleteRules(String configId);
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
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/chaining/data/datasources/request_rules_local_data_source.dart';
import 'package:getman/features/chaining/data/models/assertion_model.dart';
import 'package:getman/features/chaining/data/models/extraction_rule_model.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late RequestRulesLocalDataSourceImpl ds;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_rules_ds_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ExtractionRuleModelAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(AssertionModelAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(RequestRulesModelAdapter());
    }
    await Hive.openBox<RequestRulesModel>(HiveBoxes.requestRules);
    ds = RequestRulesLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // Build a minimal RequestRulesModel keyed by configId.
  RequestRulesModel makeRules(String configId) => RequestRulesModel(
    configId: configId,
    extractionRules: const [],
    assertions: const [],
  );

  test('getRules returns null for an unknown configId', () {
    expect(ds.getRules('missing'), isNull);
  });

  test('saveRules then getRules round-trips by configId', () async {
    await ds.saveRules(makeRules('cfg-1'));
    expect(ds.getRules('cfg-1')?.configId, 'cfg-1');
  });

  test('deleteRules removes the stored rules', () async {
    await ds.saveRules(makeRules('cfg-2'));
    await ds.deleteRules('cfg-2');
    expect(ds.getRules('cfg-2'), isNull);
  });

  test('getRules wraps a Hive failure in PersistenceException', () async {
    await Hive.box<RequestRulesModel>(HiveBoxes.requestRules).close();
    expect(() => ds.getRules('cfg-1'), throwsA(isA<PersistenceException>()));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/chaining/data/datasources/request_rules_local_data_source.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:getman/features/chaining/data/repositories/request_rules_repository_impl.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';

class _FakeRulesDataSource implements RequestRulesLocalDataSource {
  RequestRulesModel? toReturn;
  RequestRulesModel? saved;
  String? deletedConfigId;
  bool throwOnGet = false;

  @override
  RequestRulesModel? getRules(String configId) {
    if (throwOnGet) throw PersistenceException('boom');
    return toReturn;
  }

  @override
  Future<void> saveRules(RequestRulesModel rules) async => saved = rules;

  @override
  Future<void> deleteRules(String configId) async => deletedConfigId = configId;
}

void main() {
  test('getRules maps a stored model to its entity', () async {
    final entity = const RequestRulesEntity(
      configId: 'c1',
      extractionRules: [ExtractionRule(id: 'r1', targetVariable: 'tok')],
    );
    final ds = _FakeRulesDataSource()..toReturn = RequestRulesModel.fromEntity(entity);
    final repo = RequestRulesRepositoryImpl(ds);

    expect(await repo.getRules('c1'), entity);
  });

  test('getRules returns an empty entity for the configId when nothing is stored', () async {
    final ds = _FakeRulesDataSource();
    final repo = RequestRulesRepositoryImpl(ds);

    final result = await repo.getRules('c2');
    expect(result.configId, 'c2');
    expect(result.isEmpty, isTrue);
  });

  test('saveRules with a non-empty entity forwards a saveRules', () async {
    final ds = _FakeRulesDataSource();
    final repo = RequestRulesRepositoryImpl(ds);

    await repo.saveRules(const RequestRulesEntity(
      configId: 'c3',
      extractionRules: [ExtractionRule(id: 'r1', targetVariable: 'tok')],
    ));

    expect(ds.saved, isNotNull);
    expect(ds.deletedConfigId, isNull);
  });

  test('saveRules with an empty entity deletes instead of saving', () async {
    final ds = _FakeRulesDataSource();
    final repo = RequestRulesRepositoryImpl(ds);

    await repo.saveRules(const RequestRulesEntity(configId: 'c4'));

    expect(ds.deletedConfigId, 'c4');
    expect(ds.saved, isNull);
  });

  test('translates a PersistenceException into a PersistenceFailure', () async {
    final ds = _FakeRulesDataSource()..throwOnGet = true;
    final repo = RequestRulesRepositoryImpl(ds);

    expect(repo.getRules('c5'), throwsA(isA<PersistenceFailure>()));
  });
}

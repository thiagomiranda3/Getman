import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/repositories/request_rules_repository.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements RequestRulesRepository {}

class _FakeRules extends Fake implements RequestRulesEntity {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeRules()));

  late _MockRepo repo;
  setUp(() => repo = _MockRepo());

  test('GetRequestRulesUseCase delegates to repository.getRules', () async {
    final rules = _FakeRules();
    when(() => repo.getRules('cfg-1')).thenAnswer((_) async => rules);

    final result = await GetRequestRulesUseCase(repo).call('cfg-1');

    expect(result, same(rules));
    verify(() => repo.getRules('cfg-1')).called(1);
  });

  test('SaveRequestRulesUseCase delegates to repository.saveRules', () async {
    final rules = _FakeRules();
    when(() => repo.saveRules(any())).thenAnswer((_) async {});

    await SaveRequestRulesUseCase(repo).call(rules);

    verify(() => repo.saveRules(rules)).called(1);
  });
}

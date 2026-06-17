import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';
import 'package:mocktail/mocktail.dart';

class MockGet extends Mock implements GetRequestRulesUseCase {}

class MockSave extends Mock implements SaveRequestRulesUseCase {}

void main() {
  late MockGet get;
  late MockSave save;
  late RulesBloc bloc;

  setUpAll(() => registerFallbackValue(const RequestRulesEntity(configId: '')));

  setUp(() {
    get = MockGet();
    save = MockSave();
    when(() => save.call(any())).thenAnswer((_) async {});
    bloc = RulesBloc(
      getRequestRulesUseCase: get,
      saveRequestRulesUseCase: save,
    );
  });

  tearDown(() => bloc.close());

  test('LoadRules emits the loaded rules', () async {
    when(() => get.call('c1')).thenAnswer(
      (_) async => const RequestRulesEntity(
        configId: 'c1',
        assertions: [Assertion(id: 'a1')],
      ),
    );

    bloc.add(const LoadRules('c1'));
    await bloc.stream.firstWhere(
      (s) => s.rules?.configId == 'c1' && !s.isLoading,
    );

    expect(bloc.state.rules!.assertions, hasLength(1));
  });

  test('SaveRules reflects immediately and persists', () async {
    const rules = RequestRulesEntity(
      configId: 'c1',
      assertions: [Assertion(id: 'a1')],
    );

    bloc.add(const SaveRules(rules));
    await bloc.stream.firstWhere((s) => s.rules == rules);

    expect(bloc.state.rules, rules);
    verify(() => save.call(rules)).called(1);
  });

  group('AddExtractionRule', () {
    test('loads current rules, appends, and persists', () async {
      when(() => get.call('c1')).thenAnswer(
        (_) async => const RequestRulesEntity(
          configId: 'c1',
          extractionRules: [ExtractionRule(id: 'existing', expression: 'a')],
        ),
      );

      const rule = ExtractionRule(id: 'new', expression: r'$.user.id');
      bloc.add(const AddExtractionRule(configId: 'c1', rule: rule));
      await bloc.stream.firstWhere(
        (s) => (s.rules?.extractionRules.length ?? 0) == 2,
      );

      final saved =
          verify(() => save.call(captureAny())).captured.single
              as RequestRulesEntity;
      expect(saved.configId, 'c1');
      expect(saved.extractionRules.map((r) => r.id), ['existing', 'new']);
      // Bloc state reflects the appended rule.
      expect(bloc.state.rules!.extractionRules.last.expression, r'$.user.id');
    });

    test('appends to empty rules for a config with none', () async {
      when(() => get.call('c2')).thenAnswer(
        (_) async => const RequestRulesEntity(configId: 'c2'),
      );

      const rule = ExtractionRule(id: 'new', expression: r'$.token');
      bloc.add(const AddExtractionRule(configId: 'c2', rule: rule));
      await bloc.stream.firstWhere(
        (s) => (s.rules?.extractionRules.length ?? 0) == 1,
      );

      final saved =
          verify(() => save.call(captureAny())).captured.single
              as RequestRulesEntity;
      expect(saved.extractionRules.single.id, 'new');
    });
  });
}

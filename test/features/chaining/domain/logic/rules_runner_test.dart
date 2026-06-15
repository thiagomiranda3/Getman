import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/logic/assertion_engine.dart';
import 'package:getman/features/chaining/domain/logic/extraction_engine.dart';
import 'package:getman/features/chaining/domain/logic/rules_runner.dart';

void main() {
  const extractionRules = [
    ExtractionRule(id: '1', expression: 'token', targetVariable: 'tok'),
    ExtractionRule(id: '2', expression: 'user.id', targetVariable: 'uid'),
    ExtractionRule(
      id: '3',
      kind: ExtractionKind.header,
      expression: 'x-id',
      targetVariable: 'rid',
    ),
  ];
  const assertions = [
    Assertion(id: '1', expected: '200'),
    Assertion(
      id: '2',
      target: AssertionTarget.bodyJsonPath,
      path: 'token',
      expected: 'abc123',
    ),
    Assertion(
      id: '3',
      target: AssertionTarget.bodyJsonPath,
      path: 'user.id',
      comparator: AssertionComparator.exists,
    ),
  ];

  RulesRunOutput runFor(HttpResponseEntity response) => runRules(
    RulesRunInput(
      extractionRules: extractionRules,
      assertions: assertions,
      response: response,
    ),
  );

  test('runRules matches the per-engine path for a valid JSON body', () {
    const response = HttpResponseEntity(
      statusCode: 200,
      body: '{"token":"abc123","user":{"id":7}}',
      headers: {'X-Id': 'req-9'},
      durationMs: 50,
    );

    final out = runFor(response);
    final extraction = ExtractionEngine.run(extractionRules, response);
    final asserts = AssertionEngine.run(assertions, response);

    expect(
      out.extraction.map((e) => '${e.variable}=${e.value}'),
      extraction.map((e) => '${e.variable}=${e.value}'),
    );
    expect(
      out.assertions.map((a) => '${a.label}:${a.passed}'),
      asserts.map((a) => '${a.label}:${a.passed}'),
    );

    // Spot-check the actual captured values / verdicts.
    expect(out.extraction[0].value, 'abc123');
    expect(out.extraction[1].value, '7');
    expect(out.extraction[2].value, 'req-9');
    expect(out.assertions[0].passed, isTrue); // status 200
    expect(out.assertions[1].passed, isTrue); // token == abc123
    expect(out.assertions[2].passed, isTrue); // user.id exists
  });

  test('non-JSON body: jsonPath rules miss, header/status still work', () {
    const response = HttpResponseEntity(
      statusCode: 200,
      body: '<html>not json</html>',
      headers: {'X-Id': 'req-9'},
      durationMs: 10,
    );

    final out = runFor(response);
    expect(out.extraction[0].matched, isFalse); // token
    expect(out.extraction[1].matched, isFalse); // user.id
    expect(out.extraction[2].value, 'req-9'); // header still resolves
    expect(out.assertions[0].passed, isTrue); // status 200
    expect(out.assertions[1].passed, isFalse); // body token missing
    expect(out.assertions[2].passed, isFalse); // user.id exists -> false

    // Identical to the per-engine path.
    expect(
      out.assertions.map((a) => a.passed),
      AssertionEngine.run(assertions, response).map((a) => a.passed),
    );
  });

  test('empty body behaves like a parse miss', () {
    const response = HttpResponseEntity(
      statusCode: 204,
      body: '',
      headers: {},
      durationMs: 5,
    );
    final out = runFor(response);
    expect(out.extraction[0].matched, isFalse);
    expect(out.extraction[1].matched, isFalse);
    expect(out.assertions[1].passed, isFalse);
  });

  test(
    'decodes once for many jsonPath rules (results unaffected by rule count)',
    () {
      final manyRules = List.generate(
        30,
        (i) => ExtractionRule(
          id: '$i',
          expression: 'token',
          targetVariable: 'v$i',
        ),
      );
      const response = HttpResponseEntity(
        statusCode: 200,
        body: '{"token":"abc123"}',
        headers: {},
        durationMs: 1,
      );
      final out = runRules(
        RulesRunInput(
          extractionRules: manyRules,
          assertions: const [],
          response: response,
        ),
      );
      expect(out.extraction, hasLength(30));
      expect(out.extraction.every((e) => e.value == 'abc123'), isTrue);
    },
  );
}

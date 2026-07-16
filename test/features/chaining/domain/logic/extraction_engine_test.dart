import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/logic/extraction_engine.dart';

void main() {
  const response = HttpResponseEntity(
    statusCode: 200,
    body: '{"token":"abc123","user":{"id":7}}',
    headers: {'Content-Type': 'application/json', 'X-Request-Id': 'req-9'},
    durationMs: 50,
  );

  test('jsonPath rule captures a body value', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', expression: 'token', targetVariable: 'tok'),
    ], response);
    expect(results.single.variable, 'tok');
    expect(results.single.value, 'abc123');
    expect(results.single.matched, isTrue);
  });

  test('jsonPath stringifies non-string values', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', expression: 'user.id', targetVariable: 'uid'),
    ], response);
    expect(results.single.value, '7');
  });

  test('header rule is case-insensitive', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(
        id: '1',
        kind: ExtractionKind.header,
        expression: 'x-request-id',
        targetVariable: 'rid',
      ),
    ], response);
    expect(results.single.value, 'req-9');
  });

  test('regex rule returns group 1 when present', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(
        id: '1',
        kind: ExtractionKind.regex,
        expression: '"token":"([^"]+)"',
        targetVariable: 'tok',
      ),
    ], response);
    expect(results.single.value, 'abc123');
  });

  test('a miss yields matched=false / null value', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', expression: 'nope', targetVariable: 'x'),
    ], response);
    expect(results.single.matched, isFalse);
    expect(results.single.value, isNull);
  });

  test('disabled rules and empty targets are skipped', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(
        id: '1',
        expression: 'token',
        targetVariable: 'tok',
        enabled: false,
      ),
      ExtractionRule(id: '2', expression: 'token'),
    ], response);
    expect(results, isEmpty);
  });

  test('invalid regex is a miss, not a throw', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(
        id: '1',
        kind: ExtractionKind.regex,
        expression: '([',
        targetVariable: 'x',
      ),
    ], response);
    expect(results.single.matched, isFalse);
  });

  test(
    'regex alternation captures the participating group, not just group 1',
    () {
      const body = HttpResponseEntity(
        statusCode: 200,
        body: 'token: abc',
        headers: {},
        durationMs: 1,
      );
      final results = ExtractionEngine.run(const [
        ExtractionRule(
          id: '1',
          kind: ExtractionKind.regex,
          expression: r'sessionId=(\w+)|token: (\w+)',
          targetVariable: 'x',
        ),
      ], body);
      expect(results.single.matched, isTrue);
      expect(
        results.single.value,
        'abc',
        reason: 'group 1 did not participate — group 2 holds the capture',
      );
    },
  );

  test('a JSON null leaf extracts as the string "null", not a miss', () {
    const body = HttpResponseEntity(
      statusCode: 200,
      body: '{"user":{"middleName":null}}',
      headers: {},
      durationMs: 1,
    );
    final results = ExtractionEngine.run(const [
      ExtractionRule(
        id: '1',
        expression: 'user.middleName',
        targetVariable: 'x',
      ),
    ], body);
    expect(
      results.single.matched,
      isTrue,
      reason: 'the TREE view offers Extract on this exact node',
    );
    expect(results.single.value, 'null');
  });
}

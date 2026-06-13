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
      ExtractionRule(id: '1', kind: ExtractionKind.jsonPath, expression: 'token', targetVariable: 'tok'),
    ], response);
    expect(results.single.variable, 'tok');
    expect(results.single.value, 'abc123');
    expect(results.single.matched, isTrue);
  });

  test('jsonPath stringifies non-string values', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', kind: ExtractionKind.jsonPath, expression: 'user.id', targetVariable: 'uid'),
    ], response);
    expect(results.single.value, '7');
  });

  test('header rule is case-insensitive', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', kind: ExtractionKind.header, expression: 'x-request-id', targetVariable: 'rid'),
    ], response);
    expect(results.single.value, 'req-9');
  });

  test('regex rule returns group 1 when present', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', kind: ExtractionKind.regex, expression: r'"token":"([^"]+)"', targetVariable: 'tok'),
    ], response);
    expect(results.single.value, 'abc123');
  });

  test('a miss yields matched=false / null value', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', kind: ExtractionKind.jsonPath, expression: 'nope', targetVariable: 'x'),
    ], response);
    expect(results.single.matched, isFalse);
    expect(results.single.value, isNull);
  });

  test('disabled rules and empty targets are skipped', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', expression: 'token', targetVariable: 'tok', enabled: false),
      ExtractionRule(id: '2', expression: 'token', targetVariable: ''),
    ], response);
    expect(results, isEmpty);
  });

  test('invalid regex is a miss, not a throw', () {
    final results = ExtractionEngine.run(const [
      ExtractionRule(id: '1', kind: ExtractionKind.regex, expression: '([', targetVariable: 'x'),
    ], response);
    expect(results.single.matched, isFalse);
  });
}

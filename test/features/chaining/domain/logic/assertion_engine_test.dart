import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/assertion_result.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/logic/assertion_engine.dart';

void main() {
  const response = HttpResponseEntity(
    statusCode: 201,
    body: '{"ok":true,"token":"abc"}',
    headers: {'Content-Type': 'application/json'},
    durationMs: 120,
  );

  AssertionResult run(Assertion a) => AssertionEngine.run([a], response).single;

  test('status code equals', () {
    expect(run(const Assertion(id: '1', target: AssertionTarget.statusCode, expected: '201')).passed, isTrue);
    expect(run(const Assertion(id: '1', target: AssertionTarget.statusCode, expected: '200')).passed, isFalse);
  });

  test('status code in range', () {
    expect(
      run(const Assertion(id: '1', target: AssertionTarget.statusCode, comparator: AssertionComparator.inRange, expected: '200-299')).passed,
      isTrue,
    );
    expect(
      run(const Assertion(id: '1', target: AssertionTarget.statusCode, comparator: AssertionComparator.inRange, expected: '400-499')).passed,
      isFalse,
    );
  });

  test('response time lessThan / greaterThan', () {
    expect(run(const Assertion(id: '1', target: AssertionTarget.responseTime, comparator: AssertionComparator.lessThan, expected: '500')).passed, isTrue);
    expect(run(const Assertion(id: '1', target: AssertionTarget.responseTime, comparator: AssertionComparator.greaterThan, expected: '500')).passed, isFalse);
  });

  test('body JSONPath equals / contains / exists', () {
    expect(run(const Assertion(id: '1', target: AssertionTarget.bodyJsonPath, path: 'token', expected: 'abc')).passed, isTrue);
    expect(run(const Assertion(id: '1', target: AssertionTarget.bodyJsonPath, comparator: AssertionComparator.contains, path: 'token', expected: 'b')).passed, isTrue);
    expect(run(const Assertion(id: '1', target: AssertionTarget.bodyJsonPath, comparator: AssertionComparator.exists, path: 'token')).passed, isTrue);
    expect(run(const Assertion(id: '1', target: AssertionTarget.bodyJsonPath, comparator: AssertionComparator.exists, path: 'missing')).passed, isFalse);
  });

  test('header exists / equals', () {
    expect(run(const Assertion(id: '1', target: AssertionTarget.header, comparator: AssertionComparator.exists, path: 'content-type')).passed, isTrue);
    expect(run(const Assertion(id: '1', target: AssertionTarget.header, path: 'content-type', expected: 'application/json')).passed, isTrue);
  });

  test('actual value is surfaced', () {
    final r = AssertionEngine.run(const [Assertion(id: '1', target: AssertionTarget.statusCode, expected: '201')], response).single;
    expect(r.actual, '201');
    expect(r.label, contains('201'));
  });

  test('disabled assertions are skipped', () {
    final r = AssertionEngine.run(const [Assertion(id: '1', enabled: false, expected: '201')], response);
    expect(r, isEmpty);
  });
}

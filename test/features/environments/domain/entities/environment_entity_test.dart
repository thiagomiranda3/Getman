// Unit tests for EnvironmentEntity equality: variable ORDER is significant
// (B2 row reorder in the env editor) — Equatable's map equality alone is
// order-insensitive, which would suppress a pure-reorder state emission.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

void main() {
  test('same variables in the same order are equal', () {
    final a = EnvironmentEntity(
      id: 'e',
      name: 'Dev',
      variables: const {'A': '1', 'B': '2'},
    );
    final b = EnvironmentEntity(
      id: 'e',
      name: 'Dev',
      variables: const {'A': '1', 'B': '2'},
    );
    expect(a, b);
  });

  test('same variables in a different order are NOT equal', () {
    final a = EnvironmentEntity(
      id: 'e',
      name: 'Dev',
      variables: const {'A': '1', 'B': '2'},
    );
    final b = EnvironmentEntity(
      id: 'e',
      name: 'Dev',
      variables: const {'B': '2', 'A': '1'},
    );
    expect(a == b, isFalse);
  });

  test('copyWith without arguments preserves equality', () {
    final a = EnvironmentEntity(
      id: 'e',
      name: 'Dev',
      variables: const {'A': '1'},
    );
    expect(a.copyWith(), a);
  });
}

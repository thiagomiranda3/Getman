// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

ResolvedVariable _classify(String name) {
  if (name == 'apiKey') {
    return const ResolvedVariable(
      name: 'apiKey',
      kind: VariableValueKind.secret,
      value: 'shh',
      environmentName: 'Dev',
    );
  }
  return ResolvedVariable(
    name: name,
    kind: VariableValueKind.resolved,
    value: 'v-$name',
    environmentName: 'Dev',
  );
}

List<String> _names(List<VariableSuggestion> s) => [for (final x in s) x.name];

void main() {
  group('buildVariableSuggestions', () {
    test('empty query returns user vars (alpha) then dynamics', () {
      final out = buildVariableSuggestions(
        query: '',
        userVariableNames: const ['token', 'baseUrl'],
        classify: _classify,
      );
      expect(_names(out).take(2), ['baseUrl', 'token']);
      expect(_names(out), contains(r'$guid'));
    });

    test('case-insensitive filter', () {
      final out = buildVariableSuggestions(
        query: 'BASE',
        userVariableNames: const ['baseUrl', 'token'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(_names(out), ['baseUrl']);
    });

    test('prefix matches rank above substring matches', () {
      final out = buildVariableSuggestions(
        query: 'id',
        userVariableNames: const ['userId', 'id'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(_names(out), ['id', 'userId']);
    });

    test('includeDynamics false omits built-ins', () {
      final out = buildVariableSuggestions(
        query: '',
        userVariableNames: const ['x'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(_names(out), ['x']);
    });

    test('does not suggest the \$randomUuid alias', () {
      expect(kSuggestableDynamicNames, isNot(contains(r'$randomUuid')));
      expect(kSuggestableDynamicNames, contains(r'$randomUUID'));
    });

    test('carries the classification through (secret preserved)', () {
      final out = buildVariableSuggestions(
        query: 'api',
        userVariableNames: const ['apiKey'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(out.single.classification.kind, VariableValueKind.secret);
    });
  });
}

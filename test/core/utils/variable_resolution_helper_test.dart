import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

void main() {
  group('VariableResolutionHelper.classify', () {
    test('resolved variable returns value + resolved kind + env name', () {
      final r = VariableResolutionHelper.classify(
        name: 'base_url',
        variables: const {'base_url': 'https://api.example.com'},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.name, 'base_url');
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'https://api.example.com');
      expect(r.environmentName, 'Production');
    });

    test('secret variable returns secret kind with value present', () {
      final r = VariableResolutionHelper.classify(
        name: 'token',
        variables: const {'token': 'sk-123'},
        secretKeys: const {'token'},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.secret);
      expect(r.value, 'sk-123');
    });

    test('dynamic variable returns dynamicValue kind with a sample value', () {
      final r = VariableResolutionHelper.classify(
        name: r'$timestamp',
        variables: const {},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.dynamicValue);
      expect(int.tryParse(r.value ?? ''), isNotNull);
    });

    test('env var wins over a dynamic name of the same spelling', () {
      final r = VariableResolutionHelper.classify(
        name: r'$timestamp',
        variables: const {r'$timestamp': 'pinned'},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'pinned');
    });

    test('unknown variable returns unresolved with null value', () {
      final r = VariableResolutionHelper.classify(
        name: 'missing',
        variables: const {},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.unresolved);
      expect(r.value, isNull);
      expect(r.environmentName, 'Production');
    });

    test('no active environment surfaces null environmentName', () {
      final r = VariableResolutionHelper.classify(
        name: 'missing',
        variables: const {},
        secretKeys: const {},
        environmentName: null,
      );
      expect(r.kind, VariableValueKind.unresolved);
      expect(r.environmentName, isNull);
    });
  });

  group('VariableResolutionHelper.classifyLayered', () {
    test('environment value wins over collection', () {
      final r = VariableResolutionHelper.classifyLayered(
        name: 'base',
        collectionVariables: const {'base': 'collection'},
        collectionSecrets: const {},
        environmentVariables: const {'base': 'env'},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'env');
      expect(r.environmentName, 'Prod');
    });

    test('collection-only value resolves with Collection source', () {
      final r = VariableResolutionHelper.classifyLayered(
        name: 'only_c',
        collectionVariables: const {'only_c': 'c'},
        collectionSecrets: const {},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'c');
      expect(r.environmentName, 'Collection');
    });

    test('collection secret is masked as secret kind', () {
      final r = VariableResolutionHelper.classifyLayered(
        name: 'tok',
        collectionVariables: const {'tok': 's3cret'},
        collectionSecrets: const {'tok'},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: null,
      );
      expect(r.kind, VariableValueKind.secret);
      expect(r.value, 's3cret');
      expect(r.environmentName, 'Collection');
    });

    test('unknown name falls back to dynamic then unresolved', () {
      final dyn = VariableResolutionHelper.classifyLayered(
        name: r'$guid',
        collectionVariables: const {},
        collectionSecrets: const {},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(dyn.kind, VariableValueKind.dynamicValue);

      final missing = VariableResolutionHelper.classifyLayered(
        name: 'nope',
        collectionVariables: const {},
        collectionSecrets: const {},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(missing.kind, VariableValueKind.unresolved);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

void main() {
  group('LayeredVariableContext', () {
    const ctx = LayeredVariableContext(
      environmentVariables: {'host': 'env.example.com', 'token': 'secret'},
      environmentSecrets: {'token'},
      collectionVariables: {'host': 'col.example.com', 'path': '/v1'},
      environmentName: 'Staging',
    );

    test('allVariables merges with environment winning', () {
      expect(ctx.allVariables['host'], 'env.example.com'); // env wins
      expect(ctx.allVariables['path'], '/v1'); // collection-only kept
      expect(ctx.allVariables.keys, containsAll(['host', 'token', 'path']));
    });

    test('allSecretKeys unions both layers', () {
      expect(ctx.allSecretKeys, contains('token'));
    });

    test('classify reports environment source and secret kind', () {
      final t = ctx.classify('token');
      expect(t.kind, VariableValueKind.secret);
      expect(t.environmentName, 'Staging');
    });

    test('classify reports Collection source for collection-only var', () {
      final p = ctx.classify('path');
      expect(p.kind, VariableValueKind.resolved);
      expect(p.environmentName, 'Collection');
    });

    test('classify resolves dynamics and marks unknown unresolved', () {
      expect(ctx.classify(r'$guid').kind, VariableValueKind.dynamicValue);
      expect(ctx.classify('nope').kind, VariableValueKind.unresolved);
    });

    test('empty context isEmpty', () {
      expect(LayeredVariableContext.empty.isEmpty, isTrue);
      expect(ctx.isEmpty, isFalse);
    });
  });
}

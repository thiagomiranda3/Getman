import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/data/repositories/script_runtime_repository_impl.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/logic/script_diagnostic_redactor.dart';

import '../support/runtime_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fatal in [false, true]) {
    test('retains every secret assignment for display, fatal=$fatal', () async {
      final runtime = ScriptRuntimeRepositoryImpl(
        assetBundle: ScriptRuntimeTestAssets(),
      );
      addTearDown(runtime.close);
      final result = await runtime.execute(
        ScriptInput(
          executionId: 'secrets',
          tabId: 'tab',
          source:
              '''
        gm.environment.set('token', 'intermediate-secret');
        console.log(gm.environment.get('token'));
        gm.environment.set('token', 'final-secret');
        gm.environment.unset('token');
        gm.variables.set('token','temporary-secret');
        console.log(gm.variables.get('token'));
        gm.variables.unset('token');
        ${fatal ? 'while(true) {}' : ''}
      ''',
          phase: ScriptPhase.postResponse,
          config: const HttpRequestConfigEntity(id: 'request'),
          environmentId: 'env',
          environmentVariables: const {'token': 'original-secret'},
          secretKeys: const {'token'},
        ),
        cancellation: ScriptCancellation(),
        limits: const ScriptLimits(timeout: Duration(milliseconds: 100)),
      );
      expect(result.error == null, !fatal);
      expect(
        result.secretValues,
        containsAll([
          'intermediate-secret',
          'final-secret',
          'temporary-secret',
        ]),
      );
      final redact = ScriptDiagnosticRedactor(
        secretValues: result.secretValues,
      );
      expect(result.logs.map((log) => redact.redact(log.message)), [
        '••••',
        '••••',
      ]);
      expect(result.environmentPatch.sets, isEmpty);
    });
  }
  test(
    'fatal snapshot redacts logs written before a secret assignment',
    () async {
      final runtime = ScriptRuntimeRepositoryImpl(
        assetBundle: ScriptRuntimeTestAssets(),
      );
      addTearDown(runtime.close);
      final result = await runtime.execute(
        ScriptInput(
          executionId: 'late-secret',
          tabId: 'tab',
          source: '''
          console.log('captured-secret');
          gm.environment.set('token', 'captured-secret');
          while (true) {}
        ''',
          phase: ScriptPhase.postResponse,
          config: const HttpRequestConfigEntity(id: 'request'),
          environmentId: 'env',
          environmentVariables: const {'token': 'original-secret'},
          secretKeys: const {'token'},
        ),
        cancellation: ScriptCancellation(),
        limits: const ScriptLimits(timeout: Duration(milliseconds: 100)),
      );
      expect(result.error, isNotNull);
      expect(result.secretValues, contains('captured-secret'));
      final redact = ScriptDiagnosticRedactor(
        secretValues: result.secretValues,
      );
      expect(result.logs.map((entry) => redact.redact(entry.message)), [
        '••••',
      ]);
      expect(result.environmentPatch.sets, isEmpty);
    },
  );
  test(
    'prototype serializers cannot replace the private result envelope',
    () async {
      final runtime = ScriptRuntimeRepositoryImpl(
        assetBundle: ScriptRuntimeTestAssets(),
      );
      addTearDown(runtime.close);
      final result = await runtime.execute(
        ScriptInput(
          executionId: 'forge',
          tabId: 'tab',
          phase: ScriptPhase.preRequest,
          config: const HttpRequestConfigEntity(id: 'request'),
          source: """
      gm.variables.set('real','value');
      Object.prototype.toJSON=function(){
        if (!this.temporaryVariables) return this;
        return {temporaryVariables:{forged:'yes'},environmentPatch:{sets:{},unsets:[]},requestPatch:{headerSets:{},headerUnsets:[]},tests:[],logs:[],error:null};
      };
    """,
        ),
        cancellation: ScriptCancellation(),
      );
      expect(result.error, isNull);
      expect(result.temporaryVariables, {'real': 'value'});
    },
  );
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/entities/script_request_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_test_result.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/tabs/domain/entities/script_variable_snapshot.dart';

import '../../support/script_execution_harness.dart';

void main() {
  late ScriptExecutionHarness h;
  setUp(() => h = ScriptExecutionHarness());
  ScriptOutput failure(ScriptPhase phase) => ScriptOutput(
    error: ScriptError(
      kind: ScriptErrorKind.runtime,
      message: 'stop',
      phase: phase,
    ),
  );
  ScriptTestResult failed(ScriptPhase phase) =>
      ScriptTestResult(id: '1', name: 'failure', phase: phase, passed: false);
  test('no scripts retains HTTP behavior without runtime or trust', () async {
    h.trust.trusted = false;
    expect((await h.send()).response?.statusCode, 200);
    expect(h.networkCalls, 1);
    expect(h.runtime.inputs, isEmpty);
  });
  test(
    'pre request mutations and temporary vars affect only outgoing copy',
    () async {
      h.runtime.run = (input) async => ScriptOutput(
        requestPatch: ScriptRequestPatch(
          url: 'https://changed',
          headerSets: const {'token': 'jwt'},
          body: 'new',
        ),
        temporaryVariables: const {'host': 'temporary'},
      );
      await h.send(pre: 'change');
      expect(h.network.sent?.url, 'https://changed');
      expect(h.network.sent?.headers['token'], 'jwt');
      expect(h.network.sent?.body, 'new');
      expect(h.network.variables?['host'], 'temporary');
      expect(h.network.history?.url, 'https://{{host}}');
      expect(h.network.history?.body, '');
    },
  );
  test('pre runtime error prevents HTTP and commit', () async {
    h.runtime.run = (input) async => failure(input.phase);
    expect(
      (await h.send(pre: 'throw')).preRequest?.error?.kind,
      ScriptErrorKind.runtime,
    );
    expect(h.networkCalls, 0);
    expect(await h.persistedVariables(), isEmpty);
  });
  test('failed pre assertions prevent HTTP and patch', () async {
    h.runtime.run = (input) async => ScriptOutput(
      tests: [failed(input.phase)],
      environmentPatch: ScriptPatch(sets: const {'token': 'bad'}),
    );
    final result = await h.send(pre: 'assert');
    expect(result.error?.message, contains('Pre-request tests failed'));
    expect(result.preRequest?.tests.single.passed, isFalse);
    expect(h.networkCalls, 0);
    expect(await h.persistedVariables(), isEmpty);
  });
  test('pre persistence failure prevents HTTP', () async {
    h.environment.fail = true;
    h.runtime.run = (input) async =>
        ScriptOutput(environmentPatch: ScriptPatch(sets: const {'token': 'x'}));
    expect((await h.send(pre: 'set')).error?.kind, ScriptErrorKind.persistence);
    expect(h.networkCalls, 0);
  });
  test('post error preserves real response', () async {
    h.runtime.run = (input) async => failure(input.phase);
    final result = await h.send(post: 'throw');
    expect(result.response?.body, 'ok');
    expect(result.postResponse?.error?.kind, ScriptErrorKind.runtime);
  });
  test('failed post assertion permits patch', () async {
    h.runtime.run = (input) async => ScriptOutput(
      tests: [failed(input.phase)],
      environmentPatch: ScriptPatch(sets: const {'token': 'good'}),
    );
    await h.send(post: 'test');
    expect((await h.persistedVariables())['token'], 'good');
  });
  for (final status in [400, 500]) {
    test('HTTP $status runs post', () async {
      h.network.network = () async => HttpResponseEntity(
        statusCode: status,
        body: 'error',
        headers: const {},
        durationMs: 0,
      );
      await h.send(post: 'inspect');
      expect(h.runtime.inputs.single.response?.status, status);
    });
  }
  test('DNS failure never runs post', () async {
    h.network.network = () async => throw const NetworkFailure(
      'DNS',
      type: NetworkFailureType.connectionError,
    );
    await expectLater(h.send(post: 'inspect'), throwsA(isA<NetworkFailure>()));
    expect(h.runtime.inputs, isEmpty);
  });
  test('untrusted scripts never start runtime or HTTP', () async {
    h.trust.trusted = false;
    expect((await h.send(pre: 'x')).error?.kind, ScriptErrorKind.untrusted);
    expect(h.networkCalls, 0);
    expect(h.runtime.inputs, isEmpty);
  });
  test('cancel while awaiting trust prevents runtime', () async {
    final gate = Completer<bool>();
    h.trust.check = () => gate.future;
    final cancel = ScriptCancellation();
    final run = h.send(pre: 'x', cancellation: cancel);
    cancel.cancel();
    gate.complete(true);
    expect((await run).cancelled, isTrue);
    expect(h.runtime.inputs, isEmpty);
  });
  test('cancel before commit admission prevents patch', () async {
    final gate = Completer<ScriptOutput>();
    h.runtime.run = (_) => gate.future;
    final cancel = ScriptCancellation();
    final run = h.send(pre: 'x', cancellation: cancel);
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    gate.complete(
      ScriptOutput(environmentPatch: ScriptPatch(sets: const {'x': '1'})),
    );
    expect((await run).cancelled, isTrue);
    expect(h.environment.ids, isEmpty);
    expect(h.networkCalls, 0);
  });
  test(
    'cancel after admitted commit cannot undo put but prevents HTTP',
    () async {
      final admitted = Completer<void>();
      final release = Completer<void>();
      h.environment.admitted = () {
        admitted.complete();
        return release.future;
      };
      h.runtime.run = (_) async =>
          ScriptOutput(environmentPatch: ScriptPatch(sets: const {'x': '1'}));
      final cancel = ScriptCancellation();
      final run = h.send(pre: 'x', cancellation: cancel);
      await admitted.future;
      cancel.cancel();
      release.complete();
      expect((await run).cancelled, isTrue);
      expect(h.environment.values['x'], '1');
      expect(h.networkCalls, 0);
    },
  );
  test('replacement invalidates old execution after runtime await', () async {
    final gate = Completer<ScriptOutput>();
    h.runtime.run = (_) => gate.future;
    final old = h.send(pre: 'x');
    await Future<void>.delayed(Duration.zero);
    await h.send();
    gate.complete(
      ScriptOutput(environmentPatch: ScriptPatch(sets: const {'x': 'old'})),
    );
    expect((await old).cancelled, isTrue);
    expect(h.environment.values, isEmpty);
    expect(h.networkCalls, 1);
  });
  test(
    'captured environment id is used and deleted environment fails closed',
    () async {
      h.environment.deleted = true;
      h.runtime.run = (_) async =>
          ScriptOutput(environmentPatch: ScriptPatch(sets: const {'x': '1'}));
      final result = await h.send(
        pre: 'x',
        variables: ScriptVariableSnapshot(environmentId: 'captured'),
      );
      expect(result.error?.kind, ScriptErrorKind.persistence);
      expect(h.environment.ids, ['captured']);
      expect(h.networkCalls, 0);
    },
  );
  test(
    'post cancellation keeps response unpublished and prevents patch',
    () async {
      final gate = Completer<ScriptOutput>();
      h.runtime.run = (_) => gate.future;
      final cancel = ScriptCancellation();
      final run = h.send(post: 'x', cancellation: cancel);
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      gate.complete(
        ScriptOutput(environmentPatch: ScriptPatch(sets: const {'x': '1'})),
      );
      expect((await run).cancelled, isTrue);
      expect(h.environment.values, isEmpty);
    },
  );
  test(
    'secret values include captured and proposed values for redaction',
    () async {
      h.runtime.run = (input) async => ScriptOutput(
        temporaryVariables: const {'token': 'temporary'},
        environmentPatch: ScriptPatch(sets: const {'token': 'new-secret'}),
      );
      final result = await h.send(
        pre: 'x',
        variables: ScriptVariableSnapshot(
          environmentId: 'env',
          secretKeys: const {'token'},
          environmentVariables: const {'token': 'env-secret'},
          collectionVariables: const {'token': 'collection-secret'},
        ),
      );
      expect(
        result.secretValues,
        containsAll([
          'env-secret',
          'collection-secret',
          'temporary',
          'new-secret',
        ]),
      );
    },
  );
  test('next send resolves the confirmed pre patch', () async {
    h.runtime.run = (input) async => ScriptOutput(
      environmentPatch: ScriptPatch(sets: const {'token': 'confirmed'}),
    );
    await h.send(pre: 'set');
    await h.send(
      variables: ScriptVariableSnapshot(
        environmentId: 'env',
        environmentVariables: await h.persistedVariables(),
      ),
    );
    expect(h.network.variables?['token'], 'confirmed');
  });
}

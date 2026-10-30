import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_log_entry.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/entities/script_request_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_response.dart';
import 'package:getman/features/scripting/domain/entities/script_test_result.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';

void main() {
  test('source and enabled flags distinguish request scripts', () {
    const empty = RequestScripts();
    final pre = empty.copyWith(preRequest: 'const n = 1;');
    expect(empty.isEmpty, isTrue);
    expect(empty.hasEnabledScripts, isFalse);
    expect(pre, isNot(empty));
    expect(pre.hasEnabledScripts, isTrue);
    expect(pre.copyWith(preRequestEnabled: false).hasEnabledScripts, isFalse);
    expect(pre.copyWith(postResponse: 'const n = 2;'), isNot(pre));
    expect(pre.copyWith(apiVersion: 2), isNot(pre));
    expect(empty.preRequest, isEmpty);
  });

  test('patch snapshots maps and rejects conflicting changes', () {
    final values = {'token': 'first'};
    final removals = {'old'};
    final patch = ScriptPatch(sets: values, unsets: removals);
    values['token'] = 'second';
    removals.clear();
    expect(patch.sets, {'token': 'first'});
    expect(patch.unsets, {'old'});
    expect(() => patch.sets['token'] = 'changed', throwsUnsupportedError);
    expect(patch.unsets.clear, throwsUnsupportedError);
    expect(
      () => ScriptPatch(sets: const {'x': '1'}, unsets: const {'x'}),
      throwsArgumentError,
    );
    expect(patch.copyWith(sets: {'token': 'second'}), isNot(patch));
  });

  test('input snapshots variables and output cannot mutate them', () {
    final variables = {'token': 'first'};
    final input = ScriptInput(
      executionId: 'execution',
      tabId: 'tab',
      source: '',
      phase: ScriptPhase.preRequest,
      config: const HttpRequestConfigEntity(id: 'request'),
      environmentVariables: variables,
    );
    final output = ScriptOutput(temporaryVariables: variables);
    variables['token'] = 'second';
    expect(input.environmentVariables, {'token': 'first'});
    expect(output.temporaryVariables, {'token': 'first'});
    expect(output.tests.clear, throwsUnsupportedError);
    expect(input.environmentVariables.clear, throwsUnsupportedError);
  });

  test('input captures request maps independently of later editor changes', () {
    final headers = {'Authorization': 'Bearer first'};
    final auth = {'token': 'first'};
    final input = ScriptInput(
      executionId: 'execution',
      tabId: 'tab',
      source: '',
      phase: ScriptPhase.preRequest,
      config: HttpRequestConfigEntity(
        id: 'request',
        headers: headers,
        auth: auth,
      ),
    );
    headers['Authorization'] = 'Bearer second';
    auth['token'] = 'second';
    expect(input.config.headers, {'Authorization': 'Bearer first'});
    expect(input.config.auth, {'token': 'first'});
    expect(input.config.headers.clear, throwsUnsupportedError);
  });

  test('cancel is idempotent and late subscribers see cancellation', () {
    final cancellation = ScriptCancellation();
    var calls = 0;
    final remove = cancellation.onCancel(() => calls++);
    cancellation
      ..cancel()
      ..cancel();
    remove();
    cancellation.onCancel(() => calls++);
    expect(calls, 2);
    expect(cancellation.isCancelled, isTrue);
  });

  test('removed listeners are not called and unsubscribe is idempotent', () {
    final cancellation = ScriptCancellation();
    var calls = 0;
    final remove = cancellation.onCancel(() => calls++);
    remove();
    remove();
    cancellation.cancel();
    expect(calls, 0);
  });

  test(
    'copying diagnostics preserves values and can explicitly clear location',
    () {
      const error = ScriptError(
        kind: ScriptErrorKind.runtime,
        message: 'bad',
        phase: ScriptPhase.preRequest,
        line: 2,
        column: 3,
      );
      expect(error.copyWith(), error);
      expect(
        error.copyWith(line: null, column: null),
        const ScriptError(
          kind: ScriptErrorKind.runtime,
          message: 'bad',
          phase: ScriptPhase.preRequest,
        ),
      );
      expect(
        error.copyWith(
          kind: ScriptErrorKind.syntax,
          message: 'parse',
          phase: ScriptPhase.postResponse,
          line: 5,
          column: 7,
        ),
        const ScriptError(
          kind: ScriptErrorKind.syntax,
          message: 'parse',
          phase: ScriptPhase.postResponse,
          line: 5,
          column: 7,
        ),
      );
      const result = ScriptTestResult(
        id: '1',
        name: 'test',
        phase: ScriptPhase.preRequest,
        passed: false,
        message: 'failure',
      );
      expect(result.copyWith(), result);
      expect(
        result.copyWith(
          id: '2',
          name: 'next',
          phase: ScriptPhase.postResponse,
          passed: true,
          message: null,
        ),
        const ScriptTestResult(
          id: '2',
          name: 'next',
          phase: ScriptPhase.postResponse,
          passed: true,
        ),
      );
      const log = ScriptLogEntry(
        level: 'log',
        message: 'before',
        phase: ScriptPhase.preRequest,
      );
      expect(log.copyWith(), log);
      expect(
        log.copyWith(
          level: 'error',
          message: 'after',
          phase: ScriptPhase.postResponse,
        ),
        const ScriptLogEntry(
          level: 'error',
          message: 'after',
          phase: ScriptPhase.postResponse,
        ),
      );
    },
  );

  test(
    'copying response and request patches detaches their mutable inputs',
    () {
      final headers = {'Accept': 'application/json'};
      final removals = {'old'};
      final response = ScriptResponse(
        status: 200,
      ).copyWith(status: 201, durationMs: 24, text: 'ok', headers: headers);
      final patch = ScriptRequestPatch().copyWith(
        url: '/x',
        method: 'POST',
        body: '{}',
        headerSets: headers,
        headerUnsets: removals,
      );
      headers.clear();
      removals.clear();
      expect(
        response,
        ScriptResponse(
          status: 201,
          durationMs: 24,
          text: 'ok',
          headers: const {'Accept': 'application/json'},
        ),
      );
      expect(response.copyWith(), response);
      expect(response.headers.clear, throwsUnsupportedError);
      expect(
        patch,
        ScriptRequestPatch(
          url: '/x',
          method: 'POST',
          body: '{}',
          headerSets: const {'Accept': 'application/json'},
          headerUnsets: const {'old'},
        ),
      );
      expect(patch.copyWith(), patch);
      expect(patch.headerSets.clear, throwsUnsupportedError);
      expect(patch.headerUnsets.clear, throwsUnsupportedError);
      expect(
        patch
            .copyWith(
              url: null,
              method: null,
              body: null,
              headerSets: const {},
              headerUnsets: const {},
            )
            .isEmpty,
        isTrue,
      );
    },
  );

  test('copying results snapshots tests and logs and clears stage error', () {
    const error = ScriptError(
      kind: ScriptErrorKind.runtime,
      message: 'bad',
      phase: ScriptPhase.preRequest,
    );
    const result = ScriptTestResult(
      id: '1',
      name: 'test',
      phase: ScriptPhase.preRequest,
      passed: true,
    );
    const log = ScriptLogEntry(
      level: 'log',
      message: 'text',
      phase: ScriptPhase.preRequest,
    );
    final tests = [result];
    final logs = [log];
    final output = ScriptOutput().copyWith(
      temporaryVariables: const {'x': '1'},
      environmentPatch: ScriptPatch(sets: const {'y': '2'}),
      requestPatch: ScriptRequestPatch(body: '{}'),
      tests: tests,
      logs: logs,
      error: error,
      duration: const Duration(milliseconds: 3),
    );
    tests.clear();
    logs.clear();
    expect(output.tests, [result]);
    expect(output.logs, [log]);
    expect(output.logs.clear, throwsUnsupportedError);
    expect(output.copyWith(), output);
    expect(output.succeeded, isFalse);
    expect(output.copyWith(error: null).succeeded, isTrue);
    expect(output.temporaryVariables, {'x': '1'});
    expect(output.environmentPatch.sets, {'y': '2'});
    expect(output.requestPatch.body, '{}');
    expect(output.duration, const Duration(milliseconds: 3));
  });

  test('limit overrides retain independent quotas', () {
    const limits = ScriptLimits();
    expect(
      [
        limits.timeout.inMilliseconds,
        limits.memoryBytes,
        limits.sourceBytes,
        limits.inputBytes,
        limits.outputBytes,
        limits.logEntries,
        limits.logBytes,
        limits.testCount,
      ],
      [1000, 33554432, 262144, 8388608, 1048576, 200, 65536, 200],
    );
    expect(limits.copyWith(), limits);
    expect(
      limits.copyWith(
        timeout: const Duration(milliseconds: 50),
        memoryBytes: 100000,
        sourceBytes: 3000,
        inputBytes: 4000,
        outputBytes: 5000,
        logEntries: 6,
        logBytes: 700,
        testCount: 8,
      ),
      const ScriptLimits(
        timeout: Duration(milliseconds: 50),
        memoryBytes: 100000,
        sourceBytes: 3000,
        inputBytes: 4000,
        outputBytes: 5000,
        logEntries: 6,
        logBytes: 700,
        testCount: 8,
      ),
    );
  });
}

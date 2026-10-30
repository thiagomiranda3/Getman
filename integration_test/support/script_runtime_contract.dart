// Public asset-backed runtime executes the same corpus used by HTTP journeys.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/data/repositories/script_runtime_repository_impl.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';

import 'script_actions.dart';

void registerScriptRuntimeContracts() {
  test(
    'real public runtime interrupts corpus quotas and cancellation '
    'then recovers',
    () async {
      final runtime = ScriptRuntimeRepositoryImpl();
      addTearDown(runtime.close);
      ScriptInput input(String source) => ScriptInput(
        executionId: 'quota',
        tabId: 'quota-tab',
        source: source,
        phase: ScriptPhase.preRequest,
        config: const HttpRequestConfigEntity(id: 'quota'),
      );
      for (final fixture in [
        'infinite_loop.js',
        'pending_promise.js',
        'memory_limit.js',
      ]) {
        final result = await runtime.execute(
          input(await loadScriptFixture(fixture)),
          cancellation: ScriptCancellation(),
          limits: ScriptLimits(
            timeout: Duration(
              milliseconds: fixture == 'memory_limit.js' ? 3000 : 150,
            ),
            memoryBytes: 2 * 1024 * 1024,
          ),
        );
        expect(
          result.error?.kind,
          fixture == 'memory_limit.js'
              ? ScriptErrorKind.memoryLimit
              : ScriptErrorKind.timeout,
          reason: '$fixture: ${result.error?.message}',
        );
        expect(
          (await runtime.execute(
            input(await loadScriptFixture('console_limit.js')),
            cancellation: ScriptCancellation(),
          )).error,
          isNull,
        );
      }
      final cancellation = ScriptCancellation();
      final running = runtime.execute(
        input(await loadScriptFixture('infinite_loop.js')),
        cancellation: cancellation,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancellation.cancel();
      expect((await running).error?.kind, ScriptErrorKind.cancelled);
      final recovered = await runtime.execute(
        input(await loadScriptFixture('console_limit.js')),
        cancellation: ScriptCancellation(),
      );
      expect(recovered.error, isNull);
      expect(recovered.logs.length, lessThan(1000));
    },
  );
}

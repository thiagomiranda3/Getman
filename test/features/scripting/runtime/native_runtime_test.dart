// Real native engine interruption and lifecycle contract.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/data/runtime/script_runtime_factory.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman_quickjs/getman_quickjs.dart' as native;

ScriptInput input(String source) => ScriptInput(
  executionId: 'run',
  tabId: 'tab',
  source: source,
  phase: ScriptPhase.preRequest,
  config: const HttpRequestConfigEntity(id: 'request'),
);
void main() {
  test(
    'real JavaScript evaluates async syntax and reports source line',
    () async {
      final runtime = createScriptRuntime();
      addTearDown(runtime.close);
      expect(
        (await runtime.execute(
          input(
            'const a = await Promise.resolve(42); '
            'if(a !== 42) throw Error("bad");',
          ),
          cancellation: ScriptCancellation(),
        )).error,
        isNull,
      );
      final failed = await runtime.execute(
        input('const a = 1;\nthrow new Error("broken");'),
        cancellation: ScriptCancellation(),
      );
      expect(failed.error?.kind, ScriptErrorKind.runtime);
      expect(failed.error?.line, 2);
    },
  );
  test('interrupts infinite loop and pending promise and recovers', () async {
    final runtime = createScriptRuntime();
    addTearDown(runtime.close);
    for (final source in ['while(true) {}', 'await new Promise(() => {});']) {
      final result = await runtime.execute(
        input(source),
        cancellation: ScriptCancellation(),
        limits: const ScriptLimits(timeout: Duration(milliseconds: 50)),
      );
      expect(result.error?.kind, ScriptErrorKind.timeout);
    }
    expect(
      (await runtime.execute(
        input('const answer = 42;'),
        cancellation: ScriptCancellation(),
      )).error,
      isNull,
    );
  });
  test(
    'heap quota interrupts allocation and next execution is healthy',
    () async {
      final runtime = createScriptRuntime();
      addTearDown(runtime.close);
      final result = await runtime.execute(
        input(
          'const a = []; while(true) a.push(new Array(8192).fill("payload"));',
        ),
        cancellation: ScriptCancellation(),
        limits: const ScriptLimits(
          memoryBytes: 2 * 1024 * 1024,
          timeout: Duration(seconds: 3),
        ),
      );
      expect(
        result.error?.kind,
        ScriptErrorKind.memoryLimit,
        reason: result.error?.message,
      );
      expect(
        (await runtime.execute(
          input('1+1;'),
          cancellation: ScriptCancellation(),
        )).error,
        isNull,
      );
    },
  );
  test('cancels running and queued work, close drains all work', () async {
    final runtime = createScriptRuntime();
    final first = ScriptCancellation();
    final second = ScriptCancellation();
    final queued = ScriptCancellation();
    final a = runtime.execute(input('while(true) {}'), cancellation: first);
    final b = runtime.execute(input('while(true) {}'), cancellation: second);
    final c = runtime.execute(
      input('throw Error("must never run");'),
      cancellation: queued,
    );
    queued.cancel();
    expect((await c).error?.kind, ScriptErrorKind.cancelled);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    first.cancel();
    expect((await a).error?.kind, ScriptErrorKind.cancelled);
    await runtime.close();
    expect((await b).error?.kind, ScriptErrorKind.cancelled);
    expect(
      (await runtime.execute(
        input(''),
        cancellation: ScriptCancellation(),
      )).error?.kind,
      ScriptErrorKind.cancelled,
    );
  });
  test(
    'heap quota during sparse Array construction releases ownership',
    () async {
      final runtime = createScriptRuntime();
      addTearDown(runtime.close);
      // Sparse arrays exhaust object/shape allocations rather than the large
      // element buffer allocated by Array.fill. Length-property creation must
      // handle allocation failure before the object enters the GC list.
      final result = await runtime.execute(
        input(
          'const retained = []; while(true) retained.push(new Array(8192));',
        ),
        cancellation: ScriptCancellation(),
        limits: const ScriptLimits(
          memoryBytes: 2 * 1024 * 1024,
          timeout: Duration(seconds: 3),
        ),
      );
      expect(result.error?.kind, ScriptErrorKind.memoryLimit);
      expect(native.liveControls(), 0);
      expect(native.liveRuntimes(), 0);
      expect(
        (await runtime.execute(
          input('1 + 1;'),
          cancellation: ScriptCancellation(),
        )).error,
        isNull,
      );
      await runtime.close();
      expect(native.liveControls(), 0);
      expect(native.liveRuntimes(), 0);
    },
  );
  test('input quota rejects variable snapshots before execution', () async {
    final runtime = createScriptRuntime();
    addTearDown(runtime.close);
    final result = await runtime.execute(
      input('1;').copyWith(temporaryVariables: {'large': 'x' * 100}),
      cancellation: ScriptCancellation(),
      limits: const ScriptLimits(inputBytes: 50),
    );
    expect(result.error?.kind, ScriptErrorKind.inputTooLarge);
  });
  test(
    'bootstrap returns bounded private output and empty source is skipped',
    () async {
      final runtime = QuickJsRuntime(
        bootstrapSource:
            'async (input, runUser) => {await runUser({}, {}); '
            'return "x".repeat(1024);}',
        decodeOutput: (value, input, limits) =>
            throw StateError('oversized output must never decode'),
      );
      addTearDown(runtime.close);
      expect(
        (await runtime.execute(
          input(''),
          cancellation: ScriptCancellation(),
        )).error,
        isNull,
      );
      final result = await runtime.execute(
        input('1;'),
        cancellation: ScriptCancellation(),
        limits: const ScriptLimits(outputBytes: 100),
      );
      expect(result.error?.kind, ScriptErrorKind.outputTooLarge);
    },
  );
  test('third execution waits while two engines run', () async {
    final runtime = createScriptRuntime();
    addTearDown(runtime.close);
    final first = ScriptCancellation();
    final second = ScriptCancellation();
    final a = runtime.execute(input('while(true) {}'), cancellation: first);
    final b = runtime.execute(input('while(true) {}'), cancellation: second);
    var finished = false;
    final c = runtime
        .execute(
          input(
            'if(typeof fetch !== "undefined" || '
            'typeof process !== "undefined" || '
            'typeof document !== "undefined") '
            'throw Error("host leak");',
          ),
          cancellation: ScriptCancellation(),
        )
        .then((value) {
          finished = true;
          return value;
        });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(finished, isFalse);
    first.cancel();
    expect((await a).error?.kind, ScriptErrorKind.cancelled);
    expect((await c).error, isNull);
    second.cancel();
    await b;
  });
  test(
    'close releases controls and engines after every failure path',
    () async {
      final runtime = createScriptRuntime();
      expect(native.liveControls(), 0);
      expect(native.liveRuntimes(), 0);
      for (final source in [
        'throw Error("failed");',
        'while (true) {}',
        'const retained = []; while(true) retained.push(new Array(8192));',
      ]) {
        await runtime.execute(
          input(source),
          cancellation: ScriptCancellation(),
          limits: const ScriptLimits(
            timeout: Duration(milliseconds: 100),
            memoryBytes: 2 * 1024 * 1024,
          ),
        );
        expect(native.liveControls(), 0);
        expect(native.liveRuntimes(), 0);
      }
      final running = runtime.execute(
        input('while(true) {}'),
        cancellation: ScriptCancellation(),
      );
      await runtime.close();
      await running;
      expect(native.liveControls(), 0);
      expect(native.liveRuntimes(), 0);
    },
  );
}

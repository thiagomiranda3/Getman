// Standalone native runtime benchmark. Reports engine costs, not Flutter boot
// or network latency; use an AOT CLI build for the recorded measurements.
import 'dart:convert';
import 'dart:io';

import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/data/runtime/quickjs_runtime_io.dart';
import 'package:getman/features/scripting/data/runtime/script_worker_protocol.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/logic/script_output_validator.dart';
import 'package:getman_quickjs/getman_quickjs.dart' as native;

Future<void> main() async {
  final bootstrap = await File(
    'assets/scripting/gm_bootstrap.js',
  ).readAsString();
  final runtime = QuickJsRuntime(
    bootstrapSource: bootstrap,
    encodeInput: encodeScriptInput,
    decodeOutput: decodeScriptOutput,
  );
  final input = ScriptInput(
    executionId: 'benchmark',
    tabId: 'benchmark',
    source: 'gm.variables.set("answer", 6 * 7);',
    phase: ScriptPhase.preRequest,
    config: const HttpRequestConfigEntity(id: 'benchmark'),
  );
  Future<int> sample(ScriptInput input) async {
    final watch = Stopwatch()..start();
    final result = await runtime.execute(
      input,
      cancellation: ScriptCancellation(),
    );
    watch.stop();
    if (result.error != null) throw StateError(result.error!.kind.name);
    return watch.elapsedMicroseconds;
  }

  Map<String, num> summarize(List<int> values) {
    final sorted = [...values]..sort();
    return {
      'samples': values.length,
      'median_us': sorted[sorted.length ~/ 2],
      'p95_us': sorted[((sorted.length - 1) * .95).round()],
      'max_us': sorted.last,
    };
  }

  final before = ProcessInfo.currentRss;
  final bypass = <int>[];
  for (var i = 0; i < 30; i++) {
    bypass.add(await sample(input.copyWith(source: '')));
  }
  final first = await sample(input);
  for (var i = 0; i < 30; i++) {
    await sample(input);
  }
  final warmRss = ProcessInfo.currentRss;
  final repeated = <int>[];
  for (var i = 0; i < 500; i++) {
    repeated.add(await sample(input));
  }
  await runtime.close();
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'scope': 'native runtime only; no Flutter boot or HTTP latency measured',
      'platform': Platform.operatingSystem,
      'dart': Platform.version,
      'no_script_bypass': summarize(bypass),
      'first_script_us': first,
      'warm_scripts': summarize(repeated),
      'rss_before': before,
      'rss_after_warmup': warmRss,
      'rss_after_500': ProcessInfo.currentRss,
      'live_native_controls': native.liveControls(),
      'live_native_runtimes': native.liveRuntimes(),
    }),
  );
}

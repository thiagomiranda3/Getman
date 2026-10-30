// Native QuickJS execution, with two bounded isolates and native cancellation.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:getman/features/scripting/data/runtime/script_worker_protocol.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/repositories/script_runtime_repository.dart';
import 'package:getman_quickjs/getman_quickjs.dart' as native;

ScriptRuntimeRepository createScriptRuntime({
  String bootstrapSource = '',
  String Function(ScriptInput, ScriptLimits)? encodeInput,
  ScriptOutput Function(String, ScriptInput, ScriptLimits)? decodeOutput,
}) => QuickJsRuntime(
  bootstrapSource: bootstrapSource,
  encodeInput: encodeInput,
  decodeOutput: decodeOutput,
);

class QuickJsRuntime implements ScriptRuntimeRepository {
  QuickJsRuntime({
    this.bootstrapSource = '',
    this.encodeInput,
    this.decodeOutput,
  });
  final String bootstrapSource;
  final String Function(ScriptInput, ScriptLimits)? encodeInput;
  final ScriptOutput Function(String, ScriptInput, ScriptLimits)? decodeOutput;
  final List<Completer<void>> _queue = [];
  final Set<Future<void>> _running = {};
  final Set<void Function()> _cancelRunning = {};
  int _active = 0;
  bool _closed = false;

  ScriptOutput _failure(
    ScriptInput input,
    ScriptErrorKind kind,
    String message, {
    int? line,
    int? column,
  }) => ScriptOutput(
    error: ScriptError(
      kind: kind,
      message: message,
      phase: input.phase,
      line: line,
      column: column,
    ),
  );

  @override
  Future<ScriptOutput> execute(
    ScriptInput input, {
    required ScriptCancellation cancellation,
    ScriptLimits limits = const ScriptLimits(),
  }) async {
    if (_closed || cancellation.isCancelled) {
      return _failure(input, ScriptErrorKind.cancelled, 'Execution cancelled');
    }
    if (input.source.trim().isEmpty) {
      return ScriptOutput(temporaryVariables: input.temporaryVariables);
    }
    if (utf8.encode(input.source).length > limits.sourceBytes) {
      return _failure(
        input,
        ScriptErrorKind.inputTooLarge,
        'Script source exceeds limit',
      );
    }
    late final String encoded;
    try {
      encoded =
          encodeInput?.call(input, limits) ??
          jsonEncode({
            'environment': input.environmentVariables,
            'collection': input.collectionVariables,
            'temporary': input.temporaryVariables,
            'request': {
              'url': input.config.url,
              'method': input.config.method,
              'body': input.config.body,
              'headers': input.config.headers,
            },
            'response': input.response == null
                ? null
                : {
                    'text': input.response!.text,
                    'headers': input.response!.headers,
                  },
          });
    } on Object {
      return _failure(input, ScriptErrorKind.runtime, 'Invalid script input');
    }
    if (utf8.encode(encoded).length > limits.inputBytes) {
      return _failure(
        input,
        ScriptErrorKind.inputTooLarge,
        'Script input exceeds limit',
      );
    }
    while (_active >= 2) {
      final ready = Completer<void>();
      _queue.add(ready);
      final unsubscribe = cancellation.onCancel(() {
        if (!ready.isCompleted) ready.complete();
      });
      await ready.future;
      unsubscribe();
      _queue.remove(ready);
      if (_closed || cancellation.isCancelled) {
        return _failure(
          input,
          ScriptErrorKind.cancelled,
          'Execution cancelled',
        );
      }
    }
    _active++;
    final done = Completer<void>();
    _running.add(done.future);
    final stopwatch = Stopwatch()..start();
    final control = native.controlNew();
    void cancel() => native.cancel(control);
    _cancelRunning.add(cancel);
    final unsubscribe = cancellation.onCancel(cancel);
    try {
      final address = control.address;
      final prefix = bootstrapSource.isEmpty
          ? '(async () => {delete globalThis.__getmanDiagnosticSink;'
          : '($bootstrapSource)(JSON.parse(${jsonEncode(encoded)}), '
                'async function(gm, console) {';
      final suffix = bootstrapSource.isEmpty
          ? '})()'
          : '}, globalThis.__getmanDiagnosticSink)';
      final source = '$prefix\n${input.source}\n$suffix';
      final lineOffset = '\n'.allMatches(prefix).length + 1;
      final filename = 'getman-${input.phase.name}.js';
      final timeout = limits.timeout.inMilliseconds;
      final memory = limits.memoryBytes;
      final outputLimit = limits.outputBytes;
      final result = await Isolate.run(
        () => native.evaluateAddress(
          address,
          source,
          filename,
          timeout,
          memory,
          outputLimit,
        ),
      );
      if (result.$1 == 0) {
        return normalizeScriptDiagnostics(
          decodeOutput?.call(result.$2, input, limits) ??
              ScriptOutput(temporaryVariables: input.temporaryVariables),
          lineOffset,
        ).copyWith(duration: stopwatch.elapsed);
      }
      final kind = switch (result.$1) {
        2 => ScriptErrorKind.timeout,
        3 => ScriptErrorKind.cancelled,
        4 => ScriptErrorKind.memoryLimit,
        5 => ScriptErrorKind.outputTooLarge,
        _ =>
          result.$2.startsWith('SyntaxError')
              ? ScriptErrorKind.syntax
              : ScriptErrorKind.runtime,
      };
      final match = RegExp(
        r'getman-[^:]+:(\d+)(?::(\d+))?',
      ).firstMatch(result.$2);
      final line = match == null
          ? null
          : int.parse(match.group(1)!) - lineOffset;
      final failure = _failure(
        input,
        kind,
        switch (kind) {
          ScriptErrorKind.timeout => 'Script execution timed out',
          ScriptErrorKind.cancelled => 'Execution cancelled',
          ScriptErrorKind.memoryLimit => 'Script memory limit exceeded',
          ScriptErrorKind.outputTooLarge => 'Script output exceeds limit',
          _ => result.$2,
        },
        line: line == null || line < 1 ? null : line,
        column: match?.group(2) == null ? null : int.parse(match!.group(2)!),
      ).copyWith(duration: stopwatch.elapsed);
      final rawDiagnostics = result.$3;
      if (rawDiagnostics.isEmpty || decodeOutput == null) return failure;
      final retained = decodeOutput!(rawDiagnostics, input, limits);
      return failure.copyWith(
        tests: retained.tests,
        logs: retained.logs,
        secretValues: retained.secretValues,
      );
    } on Object {
      return _failure(
        input,
        ScriptErrorKind.runtime,
        'Script runtime failed',
      ).copyWith(duration: stopwatch.elapsed);
    } finally {
      unsubscribe();
      _cancelRunning.remove(cancel);
      native.controlFree(control);
      _active--;
      _running.remove(done.future);
      done.complete();
      for (final next in _queue) {
        if (!next.isCompleted) {
          next.complete();
          break;
        }
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final cancel in _cancelRunning.toList()) {
      cancel();
    }
    for (final queued in _queue) {
      if (!queued.isCompleted) queued.complete();
    }
    await Future.wait(_running.toList());
  }
}

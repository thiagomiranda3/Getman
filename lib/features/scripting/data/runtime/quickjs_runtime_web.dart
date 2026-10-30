// Offline QuickJS WASM workers with two execution slots and host cancellation.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:getman/features/scripting/data/runtime/script_worker_protocol.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/repositories/script_runtime_repository.dart';
import 'package:web/web.dart' as web;

ScriptRuntimeRepository createScriptRuntime({
  String bootstrapSource = '',
  String? workerUrl,
  String Function(ScriptInput, ScriptLimits)? encodeInput,
  ScriptOutput Function(String, ScriptInput, ScriptLimits)? decodeOutput,
}) => QuickJsRuntime(
  bootstrapSource: bootstrapSource,
  workerUrl: workerUrl,
  encodeInput: encodeInput,
  decodeOutput: decodeOutput,
);

class QuickJsRuntime implements ScriptRuntimeRepository {
  QuickJsRuntime({
    this.bootstrapSource = '',
    this.workerUrl,
    this.encodeInput,
    this.decodeOutput,
  });
  final String bootstrapSource;
  final String? workerUrl;
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
    web.Worker? worker;
    final response = Completer<Map<String, dynamic>>();
    var retainedDiagnostics = '';
    void complete(Map<String, dynamic> result) {
      if (!response.isCompleted) response.complete(result);
    }

    void cancel() {
      worker?.terminate();
      complete({
        'kind': 'cancelled',
        'message': 'Execution cancelled',
        'diagnostics': retainedDiagnostics,
      });
    }

    _cancelRunning.add(cancel);
    final unsubscribe = cancellation.onCancel(cancel);
    Timer? watchdog;
    try {
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
      // document.baseURI retains a deployed non-root base href. Flutter's
      // AssetBundle path has a second assets segment for project assets.
      final url =
          workerUrl ??
          Uri.parse(web.document.baseURI)
              .resolve(
                'assets/assets/scripting/quickjs_worker.js',
              )
              .toString();
      worker = web.Worker(url.toJS)
        ..onmessage = ((web.MessageEvent event) {
          final data = jsonDecode((event.data! as JSString).toDart);
          if (data is Map<String, dynamic>) {
            final diagnostics = data['diagnostics'];
            if (diagnostics is String &&
                utf8.encode(diagnostics).length <= limits.outputBytes) {
              retainedDiagnostics = diagnostics;
            }
            if (data['kind'] != 'diagnostic') complete(data);
          }
        }).toJS
        ..onerror = ((web.Event event) {
          complete({
            'kind': 'runtime',
            'message': 'Script worker failed to load',
          });
        }).toJS;
      watchdog = Timer(limits.timeout + const Duration(seconds: 5), () {
        worker?.terminate();
        complete({
          'kind': 'timeout',
          'message': 'Script execution timed out',
          'diagnostics': retainedDiagnostics,
        });
      });
      worker.postMessage(
        jsonEncode({
          'source': source,
          'filename': filename,
          'timeout': limits.timeout.inMilliseconds,
          'memory': limits.memoryBytes,
          'output': limits.outputBytes,
        }).toJS,
      );
      final result = await response.future;
      if (result['kind'] == 'ok') {
        return normalizeScriptDiagnostics(
          decodeOutput?.call(result['value'] as String, input, limits) ??
              ScriptOutput(temporaryVariables: input.temporaryVariables),
          lineOffset,
        ).copyWith(duration: stopwatch.elapsed);
      }
      final kind = ScriptErrorKind.values.firstWhere(
        (kind) => kind.name == result['kind'],
        orElse: () => ScriptErrorKind.runtime,
      );
      final message = result['message'] as String? ?? 'Script runtime failed';
      final match = RegExp(
        r'getman-[^:]+:(\d+)(?::(\d+))?',
      ).firstMatch(message);
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
          _ => message,
        },
        line: line == null || line < 1 ? null : line,
        column: match?.group(2) == null ? null : int.parse(match!.group(2)!),
      ).copyWith(duration: stopwatch.elapsed);
      final rawDiagnostics = result['diagnostics'] as String? ?? '';
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
      watchdog?.cancel();
      worker?.terminate();
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

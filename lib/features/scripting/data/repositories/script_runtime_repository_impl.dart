// Lazy asset loading and platform selection for the public gm API. No engine
// exists until a non-empty script is explicitly sent for execution.
import 'package:flutter/services.dart';
import 'package:getman/features/scripting/data/runtime/script_runtime_factory.dart';
import 'package:getman/features/scripting/data/runtime/script_worker_protocol.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/logic/script_output_validator.dart';
import 'package:getman/features/scripting/domain/repositories/script_runtime_repository.dart';

class ScriptRuntimeRepositoryImpl implements ScriptRuntimeRepository {
  ScriptRuntimeRepositoryImpl({AssetBundle? assetBundle})
    : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  Future<ScriptRuntimeRepository>? _runtime;
  bool _closed = false;
  Future<ScriptRuntimeRepository> _load() async => createScriptRuntime(
    bootstrapSource: await _assetBundle.loadString(
      'assets/scripting/gm_bootstrap.js',
    ),
    encodeInput: encodeScriptInput,
    decodeOutput: decodeScriptOutput,
  );

  @override
  Future<ScriptOutput> execute(
    ScriptInput input, {
    required ScriptCancellation cancellation,
    ScriptLimits limits = const ScriptLimits(),
  }) async {
    if (_closed || cancellation.isCancelled) {
      return ScriptOutput(
        error: ScriptError(
          kind: ScriptErrorKind.cancelled,
          message: 'Execution cancelled',
          phase: input.phase,
        ),
      );
    }
    if (input.source.trim().isEmpty) {
      return ScriptOutput(temporaryVariables: input.temporaryVariables);
    }
    try {
      final runtime = await (_runtime ??= _load());
      if (_closed) {
        return ScriptOutput(
          error: ScriptError(
            kind: ScriptErrorKind.cancelled,
            message: 'Execution cancelled',
            phase: input.phase,
          ),
        );
      }
      return await runtime.execute(
        input,
        cancellation: cancellation,
        limits: limits,
      );
    } on Object {
      return ScriptOutput(
        error: ScriptError(
          kind: ScriptErrorKind.runtime,
          message: 'Unable to initialize script runtime',
          phase: input.phase,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    final future = _runtime;
    if (future != null) {
      try {
        await (await future).close();
      } on Object {
        /* Loading already reported to the caller. */
      }
    }
  }
}

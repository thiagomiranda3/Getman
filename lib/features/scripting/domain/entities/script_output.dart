// One stage's result. Changes are proposals, never committed by the runtime.
import 'package:equatable/equatable.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_log_entry.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_request_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_test_result.dart';

const _unchanged = Object();

class ScriptOutput extends Equatable {
  ScriptOutput({
    Map<String, String> temporaryVariables = const {},
    ScriptPatch? environmentPatch,
    ScriptRequestPatch? requestPatch,
    List<ScriptTestResult> tests = const [],
    List<ScriptLogEntry> logs = const [],
    this.error,
    Set<String> secretValues = const {},
    this.duration = Duration.zero,
  }) : secretValues = Set.unmodifiable(secretValues),
       temporaryVariables = Map.unmodifiable(temporaryVariables),
       environmentPatch = environmentPatch ?? ScriptPatch(),
       requestPatch = requestPatch ?? ScriptRequestPatch(),
       tests = List.unmodifiable(tests),
       logs = List.unmodifiable(logs);
  final Map<String, String> temporaryVariables;
  final ScriptPatch environmentPatch;
  final ScriptRequestPatch requestPatch;
  final List<ScriptTestResult> tests;
  final List<ScriptLogEntry> logs;
  final ScriptError? error;

  /// All values assigned to existing secret keys, used for diagnostic masking.
  final Set<String> secretValues;
  final Duration duration;
  bool get succeeded => error == null;
  ScriptOutput copyWith({
    Map<String, String>? temporaryVariables,
    ScriptPatch? environmentPatch,
    ScriptRequestPatch? requestPatch,
    List<ScriptTestResult>? tests,
    List<ScriptLogEntry>? logs,
    Object? error = _unchanged,
    Set<String>? secretValues,
    Duration? duration,
  }) => ScriptOutput(
    temporaryVariables: temporaryVariables ?? this.temporaryVariables,
    environmentPatch: environmentPatch ?? this.environmentPatch,
    requestPatch: requestPatch ?? this.requestPatch,
    tests: tests ?? this.tests,
    logs: logs ?? this.logs,
    error: identical(error, _unchanged) ? this.error : error as ScriptError?,
    duration: duration ?? this.duration,
    secretValues: secretValues ?? this.secretValues,
  );
  @override
  List<Object?> get props => [
    temporaryVariables,
    environmentPatch,
    requestPatch,
    tests,
    logs,
    error,
    secretValues,
    duration,
  ];
}

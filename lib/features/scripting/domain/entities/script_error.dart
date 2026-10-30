// Immutable ScriptError value exchanged by script execution components.
import 'package:equatable/equatable.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';

const _unchanged = Object();

class ScriptError extends Equatable {
  const ScriptError({
    required this.kind,
    required this.message,
    required this.phase,
    this.line,
    this.column,
  });
  final ScriptErrorKind kind;
  final String message;
  final ScriptPhase phase;
  final int? line;
  final int? column;

  ScriptError copyWith({
    ScriptErrorKind? kind,
    String? message,
    ScriptPhase? phase,
    Object? line = _unchanged,
    Object? column = _unchanged,
  }) => ScriptError(
    kind: kind ?? this.kind,
    message: message ?? this.message,
    phase: phase ?? this.phase,
    line: identical(line, _unchanged) ? this.line : line as int?,
    column: identical(column, _unchanged) ? this.column : column as int?,
  );
  @override
  List<Object?> get props => [kind, message, phase, line, column];
}

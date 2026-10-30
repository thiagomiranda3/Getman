// Immutable ScriptLogEntry value exchanged by script execution components.
import 'package:equatable/equatable.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';

class ScriptLogEntry extends Equatable {
  const ScriptLogEntry({
    required this.level,
    required this.message,
    required this.phase,
  });
  final String level;
  final String message;
  final ScriptPhase phase;

  ScriptLogEntry copyWith({
    String? level,
    String? message,
    ScriptPhase? phase,
  }) => ScriptLogEntry(
    level: level ?? this.level,
    message: message ?? this.message,
    phase: phase ?? this.phase,
  );
  @override
  List<Object?> get props => [level, message, phase];
}

// Immutable ScriptTestResult value exchanged by script execution components.
import 'package:equatable/equatable.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';

const _unchanged = Object();

class ScriptTestResult extends Equatable {
  const ScriptTestResult({
    required this.id,
    required this.name,
    required this.phase,
    required this.passed,
    this.message,
  });
  final String id;
  final String name;
  final ScriptPhase phase;
  final bool passed;
  final String? message;

  ScriptTestResult copyWith({
    String? id,
    String? name,
    ScriptPhase? phase,
    bool? passed,
    Object? message = _unchanged,
  }) => ScriptTestResult(
    id: id ?? this.id,
    name: name ?? this.name,
    phase: phase ?? this.phase,
    passed: passed ?? this.passed,
    message: identical(message, _unchanged) ? this.message : message as String?,
  );
  @override
  List<Object?> get props => [id, name, phase, passed, message];
}

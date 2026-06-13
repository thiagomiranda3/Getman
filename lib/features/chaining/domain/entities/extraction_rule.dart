import 'package:equatable/equatable.dart';

/// Where an extraction rule reads its value from.
enum ExtractionKind {
  jsonPath('jsonPath'),
  header('header'),
  regex('regex');

  final String wire;
  const ExtractionKind(this.wire);

  static ExtractionKind fromWire(String? value) {
    for (final k in ExtractionKind.values) {
      if (k.wire == value) return k;
    }
    return ExtractionKind.jsonPath;
  }
}

/// A no-code rule that captures a value from a response into an environment
/// variable (so a later request can use `{{targetVariable}}`).
///
/// - [ExtractionKind.jsonPath]: [expression] is a JSONPath into the body.
/// - [ExtractionKind.header]: [expression] is a response header name.
/// - [ExtractionKind.regex]: [expression] is a regex over the body (group 1,
///   else group 0).
class ExtractionRule extends Equatable {
  final String id;
  final ExtractionKind kind;
  final String expression;
  final String targetVariable;
  final bool enabled;

  const ExtractionRule({
    required this.id,
    this.kind = ExtractionKind.jsonPath,
    this.expression = '',
    this.targetVariable = '',
    this.enabled = true,
  });

  ExtractionRule copyWith({
    ExtractionKind? kind,
    String? expression,
    String? targetVariable,
    bool? enabled,
  }) {
    return ExtractionRule(
      id: id,
      kind: kind ?? this.kind,
      expression: expression ?? this.expression,
      targetVariable: targetVariable ?? this.targetVariable,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  List<Object?> get props => [id, kind, expression, targetVariable, enabled];
}

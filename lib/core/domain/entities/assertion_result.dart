import 'package:equatable/equatable.dart';

/// Outcome of one assertion against a response. Self-contained display data
/// (no reference to the Assertion) so it can travel on the tab entity.
class AssertionResult extends Equatable {
  const AssertionResult({
    required this.label,
    required this.passed,
    required this.actual,
  });
  final String label;
  final bool passed;
  final String actual;

  @override
  List<Object?> get props => [label, passed, actual];
}

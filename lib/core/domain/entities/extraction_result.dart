import 'package:equatable/equatable.dart';

/// Outcome of running one extraction rule against a response. Self-contained
/// (no reference to the rule) so it can travel on the tab entity without
/// coupling the tabs feature to the chaining feature.
class ExtractionResult extends Equatable {
  final String variable;
  final String? value;
  final bool matched;

  const ExtractionResult({
    required this.variable,
    required this.value,
    required this.matched,
  });

  @override
  List<Object?> get props => [variable, value, matched];
}

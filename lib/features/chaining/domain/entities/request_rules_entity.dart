import 'package:equatable/equatable.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';

/// The extraction rules + assertions attached to a request, keyed by the
/// request config's id. Stored in its own box (not on the dedup-sensitive
/// typeId-1 config) so most requests carry no rule overhead.
class RequestRulesEntity extends Equatable {
  const RequestRulesEntity({
    required this.configId,
    this.extractionRules = const [],
    this.assertions = const [],
  });
  final String configId;
  final List<ExtractionRule> extractionRules;
  final List<Assertion> assertions;

  bool get isEmpty => extractionRules.isEmpty && assertions.isEmpty;

  RequestRulesEntity copyWith({
    List<ExtractionRule>? extractionRules,
    List<Assertion>? assertions,
  }) {
    return RequestRulesEntity(
      configId: configId,
      extractionRules: extractionRules ?? this.extractionRules,
      assertions: assertions ?? this.assertions,
    );
  }

  @override
  List<Object?> get props => [configId, extractionRules, assertions];
}

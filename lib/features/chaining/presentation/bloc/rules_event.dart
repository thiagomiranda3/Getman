import 'package:equatable/equatable.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';

abstract class RulesEvent extends Equatable {
  const RulesEvent();
  @override
  List<Object?> get props => [];
}

/// Load the rules for a request config (the active request editor's config id).
class LoadRules extends RulesEvent {
  const LoadRules(this.configId);
  final String configId;
  @override
  List<Object?> get props => [configId];
}

/// Persist + reflect edited rules.
class SaveRules extends RulesEvent {
  const SaveRules(this.rules);
  final RequestRulesEntity rules;
  @override
  List<Object?> get props => [rules];
}

import 'package:equatable/equatable.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart'
    show LoadRules;

class RulesState extends Equatable {
  const RulesState({this.rules, this.isLoading = false});

  /// The currently-loaded rules (the active request editor's). Null until a
  /// [LoadRules] completes.
  final RequestRulesEntity? rules;
  final bool isLoading;

  RulesState copyWith({RequestRulesEntity? rules, bool? isLoading}) =>
      RulesState(
        rules: rules ?? this.rules,
        isLoading: isLoading ?? this.isLoading,
      );

  @override
  List<Object?> get props => [rules, isLoading];
}

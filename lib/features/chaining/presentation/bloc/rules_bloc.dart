import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_state.dart';

/// Holds the rules for the active request editor's config. Only one rules
/// editor is mounted at a time (the active tab's), so a single loaded entity
/// is sufficient; switching tabs re-dispatches [LoadRules].
class RulesBloc extends Bloc<RulesEvent, RulesState> {
  RulesBloc({
    required GetRequestRulesUseCase getRequestRulesUseCase,
    required SaveRequestRulesUseCase saveRequestRulesUseCase,
  }) : _getRequestRulesUseCase = getRequestRulesUseCase,
       _saveRequestRulesUseCase = saveRequestRulesUseCase,
       super(const RulesState()) {
    on<LoadRules>(_onLoad);
    on<SaveRules>(_onSave);
    on<AddExtractionRule>(_onAddExtractionRule);
  }
  final GetRequestRulesUseCase _getRequestRulesUseCase;
  final SaveRequestRulesUseCase _saveRequestRulesUseCase;

  Future<void> _onLoad(LoadRules event, Emitter<RulesState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final rules = await _getRequestRulesUseCase(event.configId);
      emit(RulesState(rules: rules));
    } on PersistenceFailure catch (f) {
      log('LoadRules failed: ${f.message}', name: 'RulesBloc');
      emit(const RulesState());
    }
  }

  Future<void> _onSave(SaveRules event, Emitter<RulesState> emit) async {
    // Reflect immediately; persist best-effort.
    emit(RulesState(rules: event.rules));
    try {
      await _saveRequestRulesUseCase(event.rules);
    } on PersistenceFailure catch (f) {
      log('SaveRules failed: ${f.message}', name: 'RulesBloc');
    }
  }

  Future<void> _onAddExtractionRule(
    AddExtractionRule event,
    Emitter<RulesState> emit,
  ) async {
    // Load fresh so we append onto the persisted rules rather than whatever
    // happens to be in state (which may be a different config's rules).
    final RequestRulesEntity current;
    try {
      current = await _getRequestRulesUseCase(event.configId);
    } on PersistenceFailure catch (f) {
      log('AddExtractionRule load failed: ${f.message}', name: 'RulesBloc');
      return;
    }
    final updated = current.copyWith(
      extractionRules: [...current.extractionRules, event.rule],
    );
    emit(RulesState(rules: updated));
    try {
      await _saveRequestRulesUseCase(updated);
    } on PersistenceFailure catch (f) {
      log('AddExtractionRule save failed: ${f.message}', name: 'RulesBloc');
    }
  }
}

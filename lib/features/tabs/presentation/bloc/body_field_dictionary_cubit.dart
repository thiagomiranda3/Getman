// Shares the persisted JSON field dictionary across every request body editor.
// Only callers' positive field-count deltas are learned; loading requests and
// moving the caret must not call recordUsage. Persistence failures are logged
// without interrupting editing, and late writes never emit after disposal.
import 'dart:developer';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/repositories/body_field_dictionary_repository.dart';

class BodyFieldDictionaryState extends Equatable {
  BodyFieldDictionaryState({List<BodyFieldEntry> entries = const []})
    : entries = List.unmodifiable(entries);

  final List<BodyFieldEntry> entries;

  BodyFieldDictionaryState copyWith({List<BodyFieldEntry>? entries}) =>
      BodyFieldDictionaryState(entries: entries ?? this.entries);

  @override
  List<Object?> get props => [entries];
}

class BodyFieldDictionaryCubit extends Cubit<BodyFieldDictionaryState> {
  BodyFieldDictionaryCubit(this._repository)
    : super(BodyFieldDictionaryState(entries: _repository.entries));

  final BodyFieldDictionaryRepository _repository;

  Future<void> recordUsage(Map<String, int> increments) async {
    if (isClosed || increments.isEmpty) return;
    try {
      await _repository.recordUsage(increments);
      if (!isClosed) emit(state.copyWith(entries: _repository.entries));
    } on Failure catch (error, stackTrace) {
      log(
        'Could not learn JSON field names',
        name: 'BodyFieldDictionaryCubit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

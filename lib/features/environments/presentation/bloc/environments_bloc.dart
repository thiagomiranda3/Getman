// EnvironmentsBloc: loads/adds/updates/deletes/imports environments, each
// persisting via a single keyed Hive write (import batches the whole list).
//
// Gotchas: add/update/import re-sort the in-session list by name
// (case-insensitive) to match the data source's read-time sort -- Hive keys
// are UUIDs, so key order has no display meaning. MergeEnvironmentVariables
// reads the LIVE entity inside its handler (not a stale state snapshot) so
// two merges dispatched in the same event-loop turn both land.

import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';

class EnvironmentsBloc extends Bloc<EnvironmentsEvent, EnvironmentsState> {
  EnvironmentsBloc({
    required this._getEnvironmentsUseCase,
    required this._saveEnvironmentsUseCase,
    required this._putEnvironmentUseCase,
    required this._deleteEnvironmentUseCase,
    List<EnvironmentEntity> initialEnvironments = const [],
  }) : super(EnvironmentsState(environments: initialEnvironments)) {
    on<LoadEnvironments>(_onLoad);
    on<AddEnvironment>(_onAdd);
    on<UpdateEnvironment>(_onUpdate);
    on<MergeEnvironmentVariables>(_onMergeVariables);
    on<DeleteEnvironment>(_onDelete);
    on<ImportEnvironments>(_onImport);
  }
  final GetEnvironmentsUseCase _getEnvironmentsUseCase;
  final SaveEnvironmentsUseCase _saveEnvironmentsUseCase;
  final PutEnvironmentUseCase _putEnvironmentUseCase;
  final DeleteEnvironmentUseCase _deleteEnvironmentUseCase;

  Future<void> _onLoad(
    LoadEnvironments event,
    Emitter<EnvironmentsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final environments = await _getEnvironmentsUseCase();
      emit(state.copyWith(environments: environments, isLoading: false));
    } on PersistenceFailure catch (f) {
      log('LoadEnvironments failed: ${f.message}', name: 'EnvironmentsBloc');
      emit(state.copyWith(isLoading: false));
    }
  }

  // Add/Update persist only the touched environment (single keyed put); delete
  // is a single keyed delete. UI state is emitted first so it never blocks.
  // Both re-sort the in-session list case-insensitively by name so a
  // newly-added or renamed environment lands exactly where it will sit after
  // a restart (`EnvironmentsLocalDataSourceImpl.getEnvironments` sorts the
  // same way on read) — keys are UUIDs, so Hive's own key order carries no
  // display meaning.
  Future<void> _onAdd(
    AddEnvironment event,
    Emitter<EnvironmentsState> emit,
  ) async {
    emit(
      state.copyWith(
        environments: _sortedByName([
          ...state.environments,
          event.environment,
        ]),
      ),
    );
    await _persist(() => _putEnvironmentUseCase(event.environment));
  }

  Future<void> _onUpdate(
    UpdateEnvironment event,
    Emitter<EnvironmentsState> emit,
  ) async {
    final index = state.environments.indexWhere(
      (e) => e.id == event.environment.id,
    );
    if (index == -1) return;
    final next = [...state.environments];
    next[index] = event.environment;
    emit(state.copyWith(environments: _sortedByName(next)));
    await _persist(() => _putEnvironmentUseCase(event.environment));
  }

  /// Atomic read-modify-write: merges into the entity as it exists NOW, so
  /// two merges dispatched in the same event-loop turn both land (events are
  /// processed sequentially; each handler sees the previous one's emission).
  Future<void> _onMergeVariables(
    MergeEnvironmentVariables event,
    Emitter<EnvironmentsState> emit,
  ) async {
    if (event.variables.isEmpty) return;
    final index = state.environments.indexWhere(
      (e) => e.id == event.environmentId,
    );
    if (index == -1) return;
    final current = state.environments[index];
    final merged = current.copyWith(
      variables: {...current.variables, ...event.variables},
    );
    final next = [...state.environments];
    next[index] = merged;
    emit(state.copyWith(environments: next));
    await _persist(() => _putEnvironmentUseCase(merged));
  }

  Future<void> _onDelete(
    DeleteEnvironment event,
    Emitter<EnvironmentsState> emit,
  ) async {
    emit(
      state.copyWith(
        environments: state.environments
            .where((e) => e.id != event.id)
            .toList(),
      ),
    );
    await _persist(() => _deleteEnvironmentUseCase(event.id));
  }

  Future<void> _onImport(
    ImportEnvironments event,
    Emitter<EnvironmentsState> emit,
  ) async {
    if (event.environments.isEmpty) return;
    final next = _sortedByName([...state.environments, ...event.environments]);
    emit(state.copyWith(environments: next));
    // Import is rare and arrives as a batch — one whole-list write is fine.
    await _persist(() => _saveEnvironmentsUseCase(next));
  }

  Future<void> _persist(Future<void> Function() write) async {
    try {
      await write();
    } on PersistenceFailure catch (f) {
      log('Environments save failed: ${f.message}', name: 'EnvironmentsBloc');
    }
  }

  static List<EnvironmentEntity> _sortedByName(
    List<EnvironmentEntity> environments,
  ) =>
      [...environments]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

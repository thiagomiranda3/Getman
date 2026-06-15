import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';

class EnvironmentsBloc extends Bloc<EnvironmentsEvent, EnvironmentsState> {
  EnvironmentsBloc({
    required GetEnvironmentsUseCase getEnvironmentsUseCase,
    required SaveEnvironmentsUseCase saveEnvironmentsUseCase,
    required PutEnvironmentUseCase putEnvironmentUseCase,
    required DeleteEnvironmentUseCase deleteEnvironmentUseCase,
    List<EnvironmentEntity> initialEnvironments = const [],
  }) : _getEnvironmentsUseCase = getEnvironmentsUseCase,
       _saveEnvironmentsUseCase = saveEnvironmentsUseCase,
       _putEnvironmentUseCase = putEnvironmentUseCase,
       _deleteEnvironmentUseCase = deleteEnvironmentUseCase,
       super(EnvironmentsState(environments: initialEnvironments)) {
    on<LoadEnvironments>(_onLoad);
    on<AddEnvironment>(_onAdd);
    on<UpdateEnvironment>(_onUpdate);
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
  Future<void> _onAdd(
    AddEnvironment event,
    Emitter<EnvironmentsState> emit,
  ) async {
    emit(
      state.copyWith(environments: [...state.environments, event.environment]),
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
    emit(state.copyWith(environments: next));
    await _persist(() => _putEnvironmentUseCase(event.environment));
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
    final next = [...state.environments, ...event.environments];
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
}

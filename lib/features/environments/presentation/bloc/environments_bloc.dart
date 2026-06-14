import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';

class EnvironmentsBloc extends Bloc<EnvironmentsEvent, EnvironmentsState> {
  final GetEnvironmentsUseCase getEnvironmentsUseCase;
  final SaveEnvironmentsUseCase saveEnvironmentsUseCase;
  final PutEnvironmentUseCase putEnvironmentUseCase;
  final DeleteEnvironmentUseCase deleteEnvironmentUseCase;

  EnvironmentsBloc({
    required this.getEnvironmentsUseCase,
    required this.saveEnvironmentsUseCase,
    required this.putEnvironmentUseCase,
    required this.deleteEnvironmentUseCase,
    List<EnvironmentEntity> initialEnvironments = const [],
  }) : super(EnvironmentsState(environments: initialEnvironments)) {
    on<LoadEnvironments>(_onLoad);
    on<AddEnvironment>(_onAdd);
    on<UpdateEnvironment>(_onUpdate);
    on<DeleteEnvironment>(_onDelete);
    on<ImportEnvironments>(_onImport);
  }

  Future<void> _onLoad(LoadEnvironments event, Emitter<EnvironmentsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final environments = await getEnvironmentsUseCase();
      emit(state.copyWith(environments: environments, isLoading: false));
    } on PersistenceFailure catch (f) {
      debugPrint('LoadEnvironments failed: ${f.message}');
      emit(state.copyWith(isLoading: false));
    }
  }

  // Add/Update persist only the touched environment (single keyed put); delete
  // is a single keyed delete. UI state is emitted first so it never blocks.
  Future<void> _onAdd(AddEnvironment event, Emitter<EnvironmentsState> emit) async {
    emit(state.copyWith(environments: [...state.environments, event.environment]));
    await _persist(() => putEnvironmentUseCase(event.environment));
  }

  Future<void> _onUpdate(UpdateEnvironment event, Emitter<EnvironmentsState> emit) async {
    final index = state.environments.indexWhere((e) => e.id == event.environment.id);
    if (index == -1) return;
    final next = [...state.environments];
    next[index] = event.environment;
    emit(state.copyWith(environments: next));
    await _persist(() => putEnvironmentUseCase(event.environment));
  }

  Future<void> _onDelete(DeleteEnvironment event, Emitter<EnvironmentsState> emit) async {
    emit(state.copyWith(
      environments: state.environments.where((e) => e.id != event.id).toList(),
    ));
    await _persist(() => deleteEnvironmentUseCase(event.id));
  }

  Future<void> _onImport(ImportEnvironments event, Emitter<EnvironmentsState> emit) async {
    if (event.environments.isEmpty) return;
    final next = [...state.environments, ...event.environments];
    emit(state.copyWith(environments: next));
    // Import is rare and arrives as a batch — one whole-list write is fine here.
    await _persist(() => saveEnvironmentsUseCase(next));
  }

  Future<void> _persist(Future<void> Function() write) async {
    try {
      await write();
    } on PersistenceFailure catch (f) {
      debugPrint('Environments save failed: ${f.message}');
    }
  }
}

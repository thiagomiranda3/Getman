import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/environment_entity.dart';
import '../../domain/usecases/environments_usecases.dart';
import 'environments_event.dart';
import 'environments_state.dart';

class EnvironmentsBloc extends Bloc<EnvironmentsEvent, EnvironmentsState> {
  final GetEnvironmentsUseCase getEnvironmentsUseCase;
  final SaveEnvironmentsUseCase saveEnvironmentsUseCase;

  EnvironmentsBloc({
    required this.getEnvironmentsUseCase,
    required this.saveEnvironmentsUseCase,
  }) : super(const EnvironmentsState()) {
    on<LoadEnvironments>(_onLoad);
    on<AddEnvironment>(_onAdd);
    on<UpdateEnvironment>(_onUpdate);
    on<DeleteEnvironment>(_onDelete);
  }

  Future<void> _commit(
    Emitter<EnvironmentsState> emit,
    List<EnvironmentEntity> next,
  ) async {
    emit(state.copyWith(environments: next));
    try {
      await saveEnvironmentsUseCase(next);
    } on PersistenceFailure catch (f) {
      debugPrint('Environments save failed: ${f.message}');
    }
  }

  Future<void> _onLoad(LoadEnvironments event, Emitter<EnvironmentsState> emit) async {
    emit(state.copyWith(isLoading: true));
    final environments = await getEnvironmentsUseCase();
    emit(state.copyWith(environments: environments, isLoading: false));
  }

  Future<void> _onAdd(AddEnvironment event, Emitter<EnvironmentsState> emit) {
    final next = [...state.environments, EnvironmentEntity(name: event.name)];
    return _commit(emit, next);
  }

  Future<void> _onUpdate(UpdateEnvironment event, Emitter<EnvironmentsState> emit) {
    final index = state.environments.indexWhere((e) => e.id == event.environment.id);
    if (index == -1) return Future.value();
    final next = [...state.environments];
    next[index] = event.environment;
    return _commit(emit, next);
  }

  Future<void> _onDelete(DeleteEnvironment event, Emitter<EnvironmentsState> emit) {
    final next = state.environments.where((e) => e.id != event.id).toList();
    return _commit(emit, next);
  }
}

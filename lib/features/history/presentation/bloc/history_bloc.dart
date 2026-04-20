import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/entities/request_config_entity.dart';
import '../../domain/usecases/history_usecases.dart';
import 'history_event.dart';
import 'history_state.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  final GetHistoryUseCase getHistoryUseCase;
  final AddToHistoryUseCase addToHistoryUseCase;
  final ClearHistoryUseCase clearHistoryUseCase;
  final WatchHistoryUseCase watchHistoryUseCase;

  StreamSubscription<List<HttpRequestConfigEntity>>? _subscription;

  HistoryBloc({
    required this.getHistoryUseCase,
    required this.addToHistoryUseCase,
    required this.clearHistoryUseCase,
    required this.watchHistoryUseCase,
  }) : super(const HistoryState()) {
    on<LoadHistory>(_onLoadHistory);
    on<AddRequestToHistory>(_onAddRequestToHistory);
    on<ClearHistory>(_onClearHistory);
    on<HistoryUpdated>(_onHistoryUpdated);

    _subscription = watchHistoryUseCase().listen(
      (history) => add(HistoryUpdated(history)),
      onError: (e) => debugPrint('History watch error: $e'),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadHistory(LoadHistory event, Emitter<HistoryState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final history = await getHistoryUseCase();
      emit(state.copyWith(history: history, isLoading: false));
    } catch (e) {
      debugPrint('LoadHistory failed: $e');
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onAddRequestToHistory(AddRequestToHistory event, Emitter<HistoryState> emit) async {
    try {
      await addToHistoryUseCase(event.config, event.limit);
    } catch (e) {
      debugPrint('AddRequestToHistory failed: $e');
    }
  }

  Future<void> _onClearHistory(ClearHistory event, Emitter<HistoryState> emit) async {
    try {
      await clearHistoryUseCase();
    } catch (e) {
      debugPrint('ClearHistory failed: $e');
    }
  }

  void _onHistoryUpdated(HistoryUpdated event, Emitter<HistoryState> emit) {
    emit(state.copyWith(history: event.history, isLoading: false));
  }
}

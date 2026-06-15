import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';

/// History is read-only from the UI's perspective: writes happen inside
/// `SendRequestUseCase`, and this bloc just mirrors the box through
/// `watchHistory()` — which yields the current list on subscribe, so no
/// explicit load event is needed.
class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc({required WatchHistoryUseCase watchHistoryUseCase})
    : _watchHistoryUseCase = watchHistoryUseCase,
      super(const HistoryState(isLoading: true)) {
    on<HistoryUpdated>(_onHistoryUpdated);

    // Guard against the stream emitting during/after close() — otherwise
    // `add(HistoryUpdated)` on a closed bloc throws StateError.
    _subscription = _watchHistoryUseCase().listen(
      (history) {
        if (!isClosed) add(HistoryUpdated(history));
      },
      onError: (Object e) =>
          log('History watch error: $e', name: 'HistoryBloc'),
    );
  }
  final WatchHistoryUseCase _watchHistoryUseCase;

  StreamSubscription<List<HttpRequestConfigEntity>>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }

  void _onHistoryUpdated(HistoryUpdated event, Emitter<HistoryState> emit) {
    emit(state.copyWith(history: event.history, isLoading: false));
  }
}

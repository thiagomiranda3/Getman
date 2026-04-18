import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/history_usecases.dart';
import 'history_event.dart';
import 'history_state.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  final GetHistoryUseCase getHistoryUseCase;
  final AddToHistoryUseCase addToHistoryUseCase;
  final ClearHistoryUseCase clearHistoryUseCase;

  HistoryBloc({
    required this.getHistoryUseCase,
    required this.addToHistoryUseCase,
    required this.clearHistoryUseCase,
  }) : super(const HistoryState()) {
    on<LoadHistory>(_onLoadHistory);
    on<AddRequestToHistory>(_onAddRequestToHistory);
    on<ClearHistory>(_onClearHistory);
  }

  Future<void> _onLoadHistory(LoadHistory event, Emitter<HistoryState> emit) async {
    emit(state.copyWith(isLoading: true));
    final history = await getHistoryUseCase();
    emit(state.copyWith(history: history.reversed.toList(), isLoading: false));
  }

  Future<void> _onAddRequestToHistory(AddRequestToHistory event, Emitter<HistoryState> emit) async {
    await addToHistoryUseCase(event.config, event.limit);
    add(LoadHistory());
  }

  Future<void> _onClearHistory(ClearHistory event, Emitter<HistoryState> emit) async {
    await clearHistoryUseCase();
    emit(state.copyWith(history: []));
  }
}

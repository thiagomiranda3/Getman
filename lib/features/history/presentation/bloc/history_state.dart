import 'package:equatable/equatable.dart';
import '../../../../core/domain/entities/request_config_entity.dart';

class HistoryState extends Equatable {
  final List<HttpRequestConfigEntity> history;
  final bool isLoading;

  const HistoryState({
    this.history = const [],
    this.isLoading = false,
  });

  @override
  List<Object?> get props => [history, isLoading];

  HistoryState copyWith({
    List<HttpRequestConfigEntity>? history,
    bool? isLoading,
  }) {
    return HistoryState(
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

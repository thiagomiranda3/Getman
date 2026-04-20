import 'package:equatable/equatable.dart';
import '../../domain/entities/request_config_entity.dart';

abstract class HistoryEvent extends Equatable {
  const HistoryEvent();
  @override
  List<Object?> get props => [];
}

class LoadHistory extends HistoryEvent {
  const LoadHistory();
}

class AddRequestToHistory extends HistoryEvent {
  final HttpRequestConfigEntity config;
  final int limit;
  const AddRequestToHistory(this.config, this.limit);
  @override
  List<Object?> get props => [config, limit];
}

class ClearHistory extends HistoryEvent {
  const ClearHistory();
}

class HistoryUpdated extends HistoryEvent {
  final List<HttpRequestConfigEntity> history;
  const HistoryUpdated(this.history);
  @override
  List<Object?> get props => [history];
}

import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';

abstract class HistoryEvent extends Equatable {
  const HistoryEvent();
  @override
  List<Object?> get props => [];
}

/// Internal: dispatched by the bloc's own `watchHistory()` subscription.
class HistoryUpdated extends HistoryEvent {
  final List<HttpRequestConfigEntity> history;
  const HistoryUpdated(this.history);
  @override
  List<Object?> get props => [history];
}

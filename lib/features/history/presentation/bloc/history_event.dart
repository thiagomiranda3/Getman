import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';

abstract class HistoryEvent extends Equatable {
  const HistoryEvent();
  @override
  List<Object?> get props => [];
}

/// Internal: dispatched by the bloc's own `watchHistory()` subscription.
class HistoryUpdated extends HistoryEvent {
  const HistoryUpdated(this.history);
  final List<HttpRequestConfigEntity> history;
  @override
  List<Object?> get props => [history];
}

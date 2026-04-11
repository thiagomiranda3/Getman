import 'package:equatable/equatable.dart';
import '../../domain/entities/request_tab_entity.dart';

class TabsState extends Equatable {
  final List<HttpRequestTabEntity> tabs;
  final int activeIndex;

  const TabsState({
    this.tabs = const [],
    this.activeIndex = 0,
  });

  @override
  List<Object?> get props => [tabs, activeIndex];

  TabsState copyWith({
    List<HttpRequestTabEntity>? tabs,
    int? activeIndex,
  }) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}

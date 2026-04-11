import 'package:equatable/equatable.dart';
import '../../domain/entities/request_tab_entity.dart';

class TabsState extends Equatable {
  final List<HttpRequestTabEntity> tabs;
  final int activeIndex;
  final bool isLoading;

  const TabsState({
    this.tabs = const [],
    this.activeIndex = 0,
    this.isLoading = false,
  });

  @override
  List<Object?> get props => [tabs, activeIndex, isLoading];

  TabsState copyWith({
    List<HttpRequestTabEntity>? tabs,
    int? activeIndex,
    bool? isLoading,
  }) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

import 'package:equatable/equatable.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

class TabsState extends Equatable {
  const TabsState({
    this.panels = const [],
    this.activePanelId = '',
    this.tabs = const [],
    this.activeIndex = 0,
    this.isLoading = false,
    this.lastReaction,
    this.reactionSeq = 0,
  });

  /// All panels, in display order. Invariant: non-empty once loaded.
  final List<PanelEntity> panels;

  /// Id of the active panel (its tabs are surfaced as [tabs]/[activeIndex]).
  final String activePanelId;

  /// The ACTIVE panel's tabs — recomputed on every emit so existing widgets
  /// (and their buildWhen selectors) keep reading `state.tabs` unchanged.
  final List<HttpRequestTabEntity> tabs;

  /// Index of the active panel's active tab within [tabs].
  final int activeIndex;

  final bool isLoading;

  /// The most recent request-driven motion reaction (transient, never
  /// persisted). [reactionSeq] is monotonic across the bloc's lifetime and is
  /// carried forward by `_derive` so it never moves backwards; the
  /// ThemeReactionListener fires on each increase.
  final ThemeReaction? lastReaction;
  final int reactionSeq;

  PanelEntity? get activePanel => panels.byId(activePanelId);

  @override
  List<Object?> get props => [
    panels,
    activePanelId,
    tabs,
    activeIndex,
    isLoading,
    lastReaction,
    reactionSeq,
  ];

  TabsState copyWith({
    List<PanelEntity>? panels,
    String? activePanelId,
    List<HttpRequestTabEntity>? tabs,
    int? activeIndex,
    bool? isLoading,
    ThemeReaction? lastReaction,
    int? reactionSeq,
  }) {
    return TabsState(
      panels: panels ?? this.panels,
      activePanelId: activePanelId ?? this.activePanelId,
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      isLoading: isLoading ?? this.isLoading,
      lastReaction: lastReaction ?? this.lastReaction,
      reactionSeq: reactionSeq ?? this.reactionSeq,
    );
  }
}

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

extension PanelListLookup on Iterable<PanelEntity> {
  /// Shorthand for `firstWhereOrNull((p) => p.id == id)`.
  PanelEntity? byId(String id) => firstWhereOrNull((p) => p.id == id);
}

/// A virtual-desktop workspace grouping request tabs. Only the active panel's
/// tabs are shown in the tab strip. [tabs] may be empty — a workspace whose
/// tabs were all closed (or a freshly created panel); the UI then shows the
/// "NO OPEN TABS" placeholder. When non-empty, [activeTabId] names a tab in
/// [tabs]; it is `''` while the panel is empty.
class PanelEntity extends Equatable {
  const PanelEntity({
    required this.id,
    required this.name,
    required this.tabs,
    required this.activeTabId,
  });

  final String id;
  final String name;
  final List<HttpRequestTabEntity> tabs;
  final String activeTabId;

  PanelEntity copyWith({
    String? id,
    String? name,
    List<HttpRequestTabEntity>? tabs,
    String? activeTabId,
  }) {
    return PanelEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }

  @override
  List<Object?> get props => [id, name, tabs, activeTabId];
}

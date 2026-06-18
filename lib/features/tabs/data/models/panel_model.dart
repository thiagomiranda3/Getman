import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

part 'panel_model.g.dart';

@HiveType(typeId: 12)
class PanelModel extends HiveObject {
  PanelModel({
    required this.name,
    required this.orderedTabIds,
    required this.activeTabId,
    String? id,
  }) : id = id ?? const Uuid().v4();

  factory PanelModel.fromEntity(PanelEntity entity) => PanelModel(
    id: entity.id,
    name: entity.name,
    orderedTabIds: entity.tabs.map((t) => t.tabId).toList(),
    activeTabId: entity.activeTabId,
  );

  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<String> orderedTabIds;

  @HiveField(3)
  String activeTabId;

  /// Rebuilds the entity by mapping [orderedTabIds] through [tabsById].
  /// Ids with no live tab are skipped; the panel may rebuild empty (the bloc
  /// no longer re-seeds — an empty panel shows the "NO OPEN TABS" placeholder).
  PanelEntity toEntity(Map<String, HttpRequestTabEntity> tabsById) {
    final tabs = <HttpRequestTabEntity>[];
    for (final id in orderedTabIds) {
      final tab = tabsById[id];
      if (tab != null) tabs.add(tab);
    }
    return PanelEntity(
      id: id,
      name: name,
      tabs: tabs,
      activeTabId: activeTabId,
    );
  }
}

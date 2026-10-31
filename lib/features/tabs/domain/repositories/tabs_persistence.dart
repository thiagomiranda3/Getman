// Pure persistence contract for tabs and panels, independently of HTTP.
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

abstract class TabsPersistence {
  Future<List<HttpRequestTabEntity>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs);
  Future<void> putTab(HttpRequestTabEntity tab);
  Future<void> deleteTabs(List<String> tabIds);
  Future<void> saveTabOrder(List<String> orderedTabIds);
  Future<List<PanelEntity>> getPanels();
  Future<String?> getActivePanelId();
  Future<void> putPanel(PanelEntity panel);
  Future<void> deletePanels(List<String> panelIds);
  Future<void> savePanelMeta(List<String> panelOrder, String activePanelId);
}

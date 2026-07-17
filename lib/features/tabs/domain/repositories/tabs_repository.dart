// Abstract repository for tab/panel persistence and sending a request over
// the network; TabsBloc depends on this, never on TabsRepositoryImpl.
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

abstract class TabsRepository {
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
  Future<HttpResponseEntity> sendRequest(
    HttpRequestConfigEntity config, {
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  });
}

import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

abstract class TabsRepository {
  Future<List<HttpRequestTabEntity>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs);
  Future<void> putTab(HttpRequestTabEntity tab);
  Future<void> deleteTabs(List<String> tabIds);
  Future<void> saveTabOrder(List<String> orderedTabIds);
  Future<HttpResponseEntity> sendRequest(
    HttpRequestConfigEntity config, {
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  });
}

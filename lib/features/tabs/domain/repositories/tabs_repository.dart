import '../../../../core/network/http_response.dart';
import '../../../../core/network/network_service.dart';
import '../../../../core/domain/entities/request_config_entity.dart';
import '../entities/request_tab_entity.dart';

abstract class TabsRepository {
  Future<List<HttpRequestTabEntity>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs);
  Future<HttpResponseEntity> sendRequest(
    HttpRequestConfigEntity config, {
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  });
}

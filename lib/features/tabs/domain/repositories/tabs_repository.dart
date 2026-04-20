import '../../../../core/network/http_response.dart';
import '../../../../core/network/network_service.dart';
import '../entities/request_tab_entity.dart';

abstract class TabsRepository {
  Future<List<HttpRequestTabEntity>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs);
  Future<HttpResponseEntity> sendRequest({
    required String url,
    required String method,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? headers,
    NetworkCancelHandle? cancelHandle,
  });
}

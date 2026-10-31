// Abstract repository for tab/panel persistence and sending a request over
// the network; TabsBloc depends on this, never on TabsRepositoryImpl.
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_persistence.dart';

abstract class TabsRepository implements TabsPersistence {
  Future<HttpResponseEntity> sendRequest(
    HttpRequestConfigEntity config, {
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  });
}

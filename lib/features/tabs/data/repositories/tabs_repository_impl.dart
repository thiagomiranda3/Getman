import '../../../../core/domain/entities/request_config_entity.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/network/http_response.dart';
import '../../../../core/network/network_service.dart';
import '../../../../core/utils/environment_resolver.dart';
import '../../../../core/utils/url_query_utils.dart';
import '../../domain/entities/request_tab_entity.dart';
import '../../domain/repositories/tabs_repository.dart';
import '../datasources/tabs_local_data_source.dart';
import '../models/request_tab_model.dart';

class TabsRepositoryImpl implements TabsRepository {
  final TabsLocalDataSource localDataSource;
  final NetworkService networkService;

  TabsRepositoryImpl({
    required this.localDataSource,
    required this.networkService,
  });

  @override
  Future<List<HttpRequestTabEntity>> getTabs() => guardPersistence(() async {
    final models = await localDataSource.getTabs();
    return models.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs) => guardPersistence(() async {
    final models = tabs.map((e) => HttpRequestTabModel.fromEntity(e)).toList();
    await localDataSource.saveTabs(models);
  });

  @override
  Future<HttpResponseEntity> sendRequest(
    HttpRequestConfigEntity config, {
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  }) {
    final parts = UrlQueryUtils.parse(config.url);
    final resolvedBase = EnvironmentResolver.resolve(parts.base, envVars);

    // Duplicate keys ride through as list values — Dio (with ListFormat.multi)
    // serializes `[1, 2]` as `?key=1&key=2`.
    final queryMap = <String, List<String>>{};
    for (final p in parts.params) {
      queryMap
          .putIfAbsent(p.key, () => <String>[])
          .add(EnvironmentResolver.resolve(p.value, envVars));
    }

    final resolvedBody = config.body.isNotEmpty
        ? EnvironmentResolver.resolve(config.body, envVars)
        : null;

    return networkService.request(
      url: resolvedBase,
      method: config.method,
      queryParameters: queryMap,
      data: resolvedBody,
      headers: EnvironmentResolver.resolveMap(config.headers, envVars),
      cancelHandle: cancelHandle,
    );
  }
}

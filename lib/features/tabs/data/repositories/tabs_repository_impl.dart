import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/guard.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/request_serializer.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';

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
    final models = tabs.map(_toPersistableModel).toList();
    await localDataSource.saveTabs(models);
  });

  @override
  Future<void> putTab(HttpRequestTabEntity tab) => guardPersistence(() async {
    await localDataSource.putTab(_toPersistableModel(tab));
  });

  @override
  Future<void> deleteTabs(List<String> tabIds) => guardPersistence(() async {
    await localDataSource.deleteTabs(tabIds);
  });

  @override
  Future<void> saveTabOrder(List<String> orderedTabIds) => guardPersistence(() async {
    await localDataSource.saveOrder(orderedTabIds);
  });

  /// Maps the entity to its Hive model, replacing an over-limit response body
  /// with [kResponseBodyTooLargePlaceholder]. The in-memory session keeps the
  /// full body — only the on-disk copy is capped (see persistence_limits.dart).
  HttpRequestTabModel _toPersistableModel(HttpRequestTabEntity entity) {
    final response = entity.response;
    final capped = response != null && response.body.length > kMaxPersistedResponseBodyChars
        ? entity.copyWith(
            response: HttpResponseEntity(
              statusCode: response.statusCode,
              body: kResponseBodyTooLargePlaceholder,
              headers: response.headers,
              durationMs: response.durationMs,
            ),
          )
        : entity;
    return HttpRequestTabModel.fromEntity(capped);
  }

  @override
  Future<HttpResponseEntity> sendRequest(
    HttpRequestConfigEntity config, {
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  }) async {
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

    // Mutable copy: resolveMap can return the original (const) map verbatim
    // when there are no variables, which auth injection must not mutate.
    final headers = Map<String, String>.of(
      EnvironmentResolver.resolveMap(config.headers, envVars),
    );
    RequestSerializer.injectAuth(
      auth: AuthConfig.fromMap(config.auth),
      headers: headers,
      query: queryMap,
      envVars: envVars,
    );

    final data = await RequestSerializer.buildBody(
      config: config,
      headers: headers,
      envVars: envVars,
    );

    return networkService.request(
      url: resolvedBase,
      method: config.method,
      queryParameters: queryMap,
      data: data,
      headers: headers,
      cancelHandle: cancelHandle,
    );
  }
}

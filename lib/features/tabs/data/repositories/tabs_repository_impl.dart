import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/error/guard.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/panel_model.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/request_serializer.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:uuid/uuid.dart';

class TabsRepositoryImpl implements TabsRepository {
  TabsRepositoryImpl({
    required this.localDataSource,
    required this.networkService,
  });
  final TabsLocalDataSource localDataSource;
  final NetworkService networkService;

  @override
  Future<List<HttpRequestTabEntity>> getTabs() => guardPersistence(() async {
    final models = await localDataSource.getTabs();
    return models.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs) =>
      guardPersistence(() async {
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
  Future<void> saveTabOrder(List<String> orderedTabIds) =>
      guardPersistence(() async {
        await localDataSource.saveOrder(orderedTabIds);
      });

  @override
  Future<List<PanelEntity>> getPanels() => guardPersistence(() async {
    final tabModels = await localDataSource.getTabs();
    final tabsById = {for (final m in tabModels) m.tabId: m.toEntity()};
    final panelModels = await localDataSource.getPanels();
    if (panelModels.isEmpty) {
      if (tabsById.isEmpty) return <PanelEntity>[];
      // Legacy upgrade: wrap all existing tabs (in their saved order) into
      // one "Panel 1". The bloc persists this on first load.
      final ordered = tabModels.map((m) => m.tabId).toList();
      return [
        PanelEntity(
          id: const Uuid().v4(),
          name: 'Panel 1',
          tabs: ordered.map((id) => tabsById[id]!).toList(),
          activeTabId: ordered.first,
        ),
      ];
    }
    return panelModels.map((pm) => pm.toEntity(tabsById)).toList();
  });

  @override
  Future<String?> getActivePanelId() =>
      guardPersistence(localDataSource.getActivePanelId);

  @override
  Future<void> putPanel(PanelEntity panel) => guardPersistence(
    () => localDataSource.putPanel(PanelModel.fromEntity(panel)),
  );

  @override
  Future<void> deletePanels(List<String> panelIds) =>
      guardPersistence(() => localDataSource.deletePanels(panelIds));

  @override
  Future<void> savePanelMeta(List<String> panelOrder, String activePanelId) =>
      guardPersistence(
        () => localDataSource.savePanelMeta(panelOrder, activePanelId),
      );

  /// Maps the entity to its Hive model, replacing any over-limit response body
  /// — the displayed response and every time-travel history entry — with
  /// [kResponseBodyTooLargePlaceholder]. The in-memory session keeps the full
  /// bodies; only the on-disk copy is capped (see persistence_limits.dart).
  HttpRequestTabModel _toPersistableModel(HttpRequestTabEntity entity) {
    var capped = entity;

    final response = capped.response;
    if (response != null &&
        response.body.length > kMaxPersistedResponseBodyChars) {
      capped = capped.copyWith(
        response: response.copyWithBody(kResponseBodyTooLargePlaceholder),
      );
    }

    if (capped.responseHistory.any(
      (e) => e.response.body.length > kMaxPersistedResponseBodyChars,
    )) {
      capped = capped.copyWith(
        responseHistory: capped.responseHistory
            .map(
              (e) => e.response.body.length > kMaxPersistedResponseBodyChars
                  ? e.copyWith(
                      response: e.response.copyWithBody(
                        kResponseBodyTooLargePlaceholder,
                      ),
                    )
                  : e,
            )
            .toList(),
      );
    }

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

    final dynamic data;
    try {
      data = await RequestSerializer.buildBody(
        config: config,
        headers: headers,
        envVars: envVars,
      );
    } on FileBodyException catch (e) {
      // A missing/unreadable file body is a real, user-visible error — surface
      // it as a NetworkFailure (statusCode 0) so the response panel + history
      // show it, rather than letting an uncaught throw silently drop the send.
      throw NetworkFailure(
        'Could not read file: ${e.path}',
        type: NetworkFailureType.unknown,
        statusCode: 0,
      );
    } on GraphqlVariablesException catch (e) {
      // Invalid GraphQL variables are a real, user-visible error — surface as a
      // status-0 NetworkFailure so the response panel + history show it.
      throw NetworkFailure(
        e.toString(),
        type: NetworkFailureType.unknown,
        statusCode: 0,
      );
    }

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

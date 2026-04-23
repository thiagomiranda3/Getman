import '../../../../core/domain/entities/request_config_entity.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/network/http_response.dart';
import '../../../../core/network/network_service.dart';
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
    NetworkCancelHandle? cancelHandle,
  }) {
    return networkService.request(
      url: config.url,
      method: config.method,
      queryParameters: config.params,
      data: config.body.isNotEmpty ? config.body : null,
      headers: config.headers,
      cancelHandle: cancelHandle,
    );
  }
}

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
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
  Future<List<HttpRequestTabEntity>> getTabs() async {
    try {
      final models = await localDataSource.getTabs();
      return models.map((m) => m.toEntity()).toList();
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }

  @override
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs) async {
    try {
      final models = tabs.map((e) => HttpRequestTabModel.fromEntity(e)).toList();
      await localDataSource.saveTabs(models);
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }

  @override
  Future<HttpResponseEntity> sendRequest({
    required String url,
    required String method,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? headers,
    NetworkCancelHandle? cancelHandle,
  }) {
    return networkService.request(
      url: url,
      method: method,
      queryParameters: queryParameters,
      data: data,
      headers: headers,
      cancelHandle: cancelHandle,
    );
  }
}

import '../../domain/entities/request_tab_entity.dart';
import '../../domain/repositories/tabs_repository.dart';
import '../datasources/tabs_local_data_source.dart';
import '../models/request_tab_model.dart';

class TabsRepositoryImpl implements TabsRepository {
  final TabsLocalDataSource localDataSource;

  TabsRepositoryImpl(this.localDataSource);

  @override
  Future<List<HttpRequestTabEntity>> getTabs() async {
    final models = await localDataSource.getTabs();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs) async {
    final models = tabs.map((e) => HttpRequestTabModel.fromEntity(e)).toList();
    await localDataSource.saveTabs(models);
  }
}

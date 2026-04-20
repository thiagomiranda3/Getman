import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/request_tab_entity.dart';
import '../../domain/repositories/tabs_repository.dart';
import '../datasources/tabs_local_data_source.dart';
import '../models/request_tab_model.dart';

class TabsRepositoryImpl implements TabsRepository {
  final TabsLocalDataSource localDataSource;

  TabsRepositoryImpl(this.localDataSource);

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
}

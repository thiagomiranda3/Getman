import '../entities/request_tab_entity.dart';

abstract class TabsRepository {
  Future<List<HttpRequestTabEntity>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs);
}

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/settings_entity.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';
import '../models/settings_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource localDataSource;

  SettingsRepositoryImpl(this.localDataSource);

  @override
  Future<SettingsEntity> getSettings() async {
    try {
      final model = await localDataSource.getSettings();
      return model.toEntity();
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }

  @override
  Future<void> saveSettings(SettingsEntity settings) async {
    try {
      final model = SettingsModel.fromEntity(settings);
      await localDataSource.saveSettings(model);
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }
}

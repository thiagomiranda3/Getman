import 'package:getman/core/error/guard.dart';
import 'package:getman/features/settings/data/datasources/settings_local_data_source.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this.localDataSource);
  final SettingsLocalDataSource localDataSource;

  @override
  Future<SettingsEntity> getSettings() => guardPersistence(() async {
    final model = await localDataSource.getSettings();
    return model.toEntity();
  });

  @override
  Future<void> saveSettings(SettingsEntity settings) =>
      guardPersistence(() async {
        await localDataSource.saveSettings(SettingsModel.fromEntity(settings));
      });
}

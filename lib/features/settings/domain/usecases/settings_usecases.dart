import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';

class GetSettingsUseCase {
  GetSettingsUseCase(this.repository);
  final SettingsRepository repository;
  Future<SettingsEntity> call() => repository.getSettings();
}

class SaveSettingsUseCase {
  SaveSettingsUseCase(this.repository);
  final SettingsRepository repository;
  Future<void> call(SettingsEntity settings) =>
      repository.saveSettings(settings);
}

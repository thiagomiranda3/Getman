import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';

class GetSettingsUseCase {
  final SettingsRepository repository;
  GetSettingsUseCase(this.repository);
  Future<SettingsEntity> call() => repository.getSettings();
}

class SaveSettingsUseCase {
  final SettingsRepository repository;
  SaveSettingsUseCase(this.repository);
  Future<void> call(SettingsEntity settings) => repository.saveSettings(settings);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/settings/data/datasources/settings_local_data_source.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

class _FakeSettingsDataSource implements SettingsLocalDataSource {
  SettingsModel toReturn;
  SettingsModel? saved;
  bool throwOnGet = false;
  _FakeSettingsDataSource(this.toReturn);

  @override
  Future<SettingsModel> getSettings() async {
    if (throwOnGet) throw PersistenceException('boom');
    return toReturn;
  }

  @override
  Future<void> saveSettings(SettingsModel settings) async => saved = settings;
}

void main() {
  test('getSettings maps the stored model back to an entity', () async {
    const entity = SettingsEntity(historyLimit: 42, isDarkMode: true);
    final ds = _FakeSettingsDataSource(SettingsModel.fromEntity(entity));
    final repo = SettingsRepositoryImpl(ds);

    expect(await repo.getSettings(), entity);
  });

  test('saveSettings converts the entity to a model and forwards it', () async {
    const entity = SettingsEntity(historyLimit: 7);
    final ds = _FakeSettingsDataSource(SettingsModel.fromEntity(const SettingsEntity()));
    final repo = SettingsRepositoryImpl(ds);

    await repo.saveSettings(entity);

    expect(ds.saved, isNotNull);
    expect(ds.saved!.historyLimit, 7);
  });

  test('translates a PersistenceException into a PersistenceFailure', () async {
    final ds = _FakeSettingsDataSource(SettingsModel.fromEntity(const SettingsEntity()))
      ..throwOnGet = true;
    final repo = SettingsRepositoryImpl(ds);

    expect(repo.getSettings(), throwsA(isA<PersistenceFailure>()));
  });
}

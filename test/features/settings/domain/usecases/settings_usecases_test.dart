import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements SettingsRepository {}

class _FakeSettings extends Fake implements SettingsEntity {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeSettings()));

  late _MockRepo repo;
  setUp(() => repo = _MockRepo());

  test('GetSettingsUseCase delegates to repository.getSettings', () async {
    final settings = _FakeSettings();
    when(() => repo.getSettings()).thenAnswer((_) async => settings);

    final result = await GetSettingsUseCase(repo).call();

    expect(result, same(settings));
    verify(() => repo.getSettings()).called(1);
  });

  test('SaveSettingsUseCase delegates to repository.saveSettings', () async {
    final settings = _FakeSettings();
    when(() => repo.saveSettings(any())).thenAnswer((_) async {});

    await SaveSettingsUseCase(repo).call(settings);

    verify(() => repo.saveSettings(settings)).called(1);
  });
}

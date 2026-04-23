import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

void main() {
  group('SettingsModel themeId', () {
    test('fromEntity default themeId is brutalist', () {
      final model = SettingsModel.fromEntity(const SettingsEntity());
      expect(model.themeId, 'brutalist');
    });

    test('json roundtrip preserves themeId', () {
      final model = SettingsModel(themeId: 'editorial');
      final roundTripped = SettingsModel.fromJson(model.toJson());
      expect(roundTripped.themeId, 'editorial');
    });

    test('entity roundtrip preserves themeId', () {
      const entity = SettingsEntity(themeId: 'editorial');
      final model = SettingsModel.fromEntity(entity);
      expect(model.toEntity().themeId, 'editorial');
    });

    test('copyWith overrides themeId but keeps other fields', () {
      final original = SettingsModel(themeId: 'brutalist', historyLimit: 50);
      final copy = original.copyWith(themeId: 'editorial');
      expect(copy.themeId, 'editorial');
      expect(copy.historyLimit, 50);
    });
  });

  group('SettingsModel activeEnvironmentId', () {
    test('default is null', () {
      expect(const SettingsEntity().activeEnvironmentId, isNull);
      expect(SettingsModel().activeEnvironmentId, isNull);
    });

    test('entity roundtrip preserves a set id', () {
      const entity = SettingsEntity(activeEnvironmentId: 'env-42');
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.activeEnvironmentId, 'env-42');
    });

    test('entity roundtrip preserves null', () {
      const entity = SettingsEntity(activeEnvironmentId: null);
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.activeEnvironmentId, isNull);
    });

    test('json roundtrip preserves id', () {
      final model = SettingsModel(activeEnvironmentId: 'x');
      expect(SettingsModel.fromJson(model.toJson()).activeEnvironmentId, 'x');
    });

    test('SettingsEntity.copyWith can clear to null explicitly', () {
      const entity = SettingsEntity(activeEnvironmentId: 'x');
      final cleared = entity.copyWith(activeEnvironmentId: null);
      expect(cleared.activeEnvironmentId, isNull);
    });

    test('SettingsEntity.copyWith without arg preserves previous id', () {
      const entity = SettingsEntity(activeEnvironmentId: 'x');
      final preserved = entity.copyWith(themeId: 'other');
      expect(preserved.activeEnvironmentId, 'x');
    });
  });
}

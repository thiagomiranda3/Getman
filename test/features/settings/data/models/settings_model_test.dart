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
}

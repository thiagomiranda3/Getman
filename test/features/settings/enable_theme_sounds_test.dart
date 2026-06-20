import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

void main() {
  test('defaults to false; round-trips through model + json', () {
    const entity = SettingsEntity();
    expect(entity.enableThemeSounds, isFalse);

    final model = SettingsModel.fromEntity(
      entity.copyWith(enableThemeSounds: true),
    );
    expect(model.enableThemeSounds, isTrue);
    expect(model.toEntity().enableThemeSounds, isTrue);

    final json = model.toJson();
    expect(json['enableThemeSounds'], isTrue);
    expect(SettingsModel.fromJson(json).enableThemeSounds, isTrue);
  });
}

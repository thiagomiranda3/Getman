import 'package:equatable/equatable.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

class SettingsState extends Equatable {
  const SettingsState({required this.settings});

  factory SettingsState.initial() =>
      const SettingsState(settings: SettingsEntity());
  final SettingsEntity settings;

  @override
  List<Object?> get props => [settings];

  SettingsState copyWith({SettingsEntity? settings}) {
    return SettingsState(settings: settings ?? this.settings);
  }
}

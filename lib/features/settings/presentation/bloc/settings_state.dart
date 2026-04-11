import 'package:equatable/equatable.dart';
import '../../domain/entities/settings_entity.dart';

class SettingsState extends Equatable {
  final SettingsEntity settings;

  const SettingsState({required this.settings});

  factory SettingsState.initial() => const SettingsState(settings: SettingsEntity());

  @override
  List<Object?> get props => [settings];

  SettingsState copyWith({SettingsEntity? settings}) {
    return SettingsState(settings: settings ?? this.settings);
  }
}

import 'package:equatable/equatable.dart';
import '../../domain/entities/settings_entity.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class LoadSettings extends SettingsEvent {}

class UpdateDarkMode extends SettingsEvent {
  final bool isDarkMode;
  const UpdateDarkMode(this.isDarkMode);
  @override
  List<Object?> get props => [isDarkMode];
}

class UpdateCompactMode extends SettingsEvent {
  final bool isCompactMode;
  const UpdateCompactMode(this.isCompactMode);
  @override
  List<Object?> get props => [isCompactMode];
}

class UpdateVerticalLayout extends SettingsEvent {
  final bool isVerticalLayout;
  const UpdateVerticalLayout(this.isVerticalLayout);
  @override
  List<Object?> get props => [isVerticalLayout];
}

class UpdateHistoryLimit extends SettingsEvent {
  final int historyLimit;
  const UpdateHistoryLimit(this.historyLimit);
  @override
  List<Object?> get props => [historyLimit];
}

class UpdateSaveResponseInHistory extends SettingsEvent {
  final bool save;
  const UpdateSaveResponseInHistory(this.save);
  @override
  List<Object?> get props => [save];
}

class UpdateSplitRatio extends SettingsEvent {
  final double ratio;
  const UpdateSplitRatio(this.ratio);
  @override
  List<Object?> get props => [ratio];
}

class UpdateSideMenuWidth extends SettingsEvent {
  final double width;
  const UpdateSideMenuWidth(this.width);
  @override
  List<Object?> get props => [width];
}

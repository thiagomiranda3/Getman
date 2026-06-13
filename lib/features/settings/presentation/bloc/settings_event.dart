import 'package:equatable/equatable.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

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

class UpdateThemeId extends SettingsEvent {
  final String themeId;
  const UpdateThemeId(this.themeId);
  @override
  List<Object?> get props => [themeId];
}

class UpdateActiveEnvironmentId extends SettingsEvent {
  final String? id;
  const UpdateActiveEnvironmentId(this.id);
  @override
  List<Object?> get props => [id];
}

class UpdateConnectTimeout extends SettingsEvent {
  final int ms;
  const UpdateConnectTimeout(this.ms);
  @override
  List<Object?> get props => [ms];
}

class UpdateSendTimeout extends SettingsEvent {
  final int ms;
  const UpdateSendTimeout(this.ms);
  @override
  List<Object?> get props => [ms];
}

class UpdateReceiveTimeout extends SettingsEvent {
  final int ms;
  const UpdateReceiveTimeout(this.ms);
  @override
  List<Object?> get props => [ms];
}

class UpdateFollowRedirects extends SettingsEvent {
  final bool value;
  const UpdateFollowRedirects(this.value);
  @override
  List<Object?> get props => [value];
}

class UpdateVerifySsl extends SettingsEvent {
  final bool value;
  const UpdateVerifySsl(this.value);
  @override
  List<Object?> get props => [value];
}

class UpdateProxyUrl extends SettingsEvent {
  final String? url;
  const UpdateProxyUrl(this.url);
  @override
  List<Object?> get props => [url];
}

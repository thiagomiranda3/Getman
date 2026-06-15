import 'package:equatable/equatable.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class UpdateDarkMode extends SettingsEvent {
  const UpdateDarkMode({required this.isDarkMode});
  final bool isDarkMode;
  @override
  List<Object?> get props => [isDarkMode];
}

class UpdateCompactMode extends SettingsEvent {
  const UpdateCompactMode({required this.isCompactMode});
  final bool isCompactMode;
  @override
  List<Object?> get props => [isCompactMode];
}

class UpdateVerticalLayout extends SettingsEvent {
  const UpdateVerticalLayout({required this.isVerticalLayout});
  final bool isVerticalLayout;
  @override
  List<Object?> get props => [isVerticalLayout];
}

class UpdateHistoryLimit extends SettingsEvent {
  const UpdateHistoryLimit(this.historyLimit);
  final int historyLimit;
  @override
  List<Object?> get props => [historyLimit];
}

class UpdateSaveResponseInHistory extends SettingsEvent {
  const UpdateSaveResponseInHistory({required this.save});
  final bool save;
  @override
  List<Object?> get props => [save];
}

class UpdateAlwaysPrettifyLargeResponses extends SettingsEvent {
  const UpdateAlwaysPrettifyLargeResponses({required this.value});
  final bool value;
  @override
  List<Object?> get props => [value];
}

class UpdateSplitRatio extends SettingsEvent {
  const UpdateSplitRatio(this.ratio);
  final double ratio;
  @override
  List<Object?> get props => [ratio];
}

class UpdateSideMenuWidth extends SettingsEvent {
  const UpdateSideMenuWidth(this.width);
  final double width;
  @override
  List<Object?> get props => [width];
}

class UpdateThemeId extends SettingsEvent {
  const UpdateThemeId(this.themeId);
  final String themeId;
  @override
  List<Object?> get props => [themeId];
}

class UpdateActiveEnvironmentId extends SettingsEvent {
  const UpdateActiveEnvironmentId(this.id);
  final String? id;
  @override
  List<Object?> get props => [id];
}

class UpdateConnectTimeout extends SettingsEvent {
  const UpdateConnectTimeout(this.ms);
  final int ms;
  @override
  List<Object?> get props => [ms];
}

class UpdateSendTimeout extends SettingsEvent {
  const UpdateSendTimeout(this.ms);
  final int ms;
  @override
  List<Object?> get props => [ms];
}

class UpdateReceiveTimeout extends SettingsEvent {
  const UpdateReceiveTimeout(this.ms);
  final int ms;
  @override
  List<Object?> get props => [ms];
}

class UpdateFollowRedirects extends SettingsEvent {
  const UpdateFollowRedirects({required this.value});
  final bool value;
  @override
  List<Object?> get props => [value];
}

class UpdateMaxRedirects extends SettingsEvent {
  const UpdateMaxRedirects(this.value);
  final int value;
  @override
  List<Object?> get props => [value];
}

class UpdateVerifySsl extends SettingsEvent {
  const UpdateVerifySsl({required this.value});
  final bool value;
  @override
  List<Object?> get props => [value];
}

/// Replaces the full client-certificate (mTLS) trio. Each field is applied
/// explicitly (null clears it), so callers send the whole current trio with one
/// field changed, or all-null to disconnect.
class UpdateClientCertificate extends SettingsEvent {
  const UpdateClientCertificate({this.certPath, this.keyPath, this.passphrase});
  final String? certPath;
  final String? keyPath;
  final String? passphrase;
  @override
  List<Object?> get props => [certPath, keyPath, passphrase];
}

class UpdateProxyUrl extends SettingsEvent {
  const UpdateProxyUrl(this.url);
  final String? url;
  @override
  List<Object?> get props => [url];
}

class UpdateWorkspacePath extends SettingsEvent {
  const UpdateWorkspacePath(this.path, {this.bookmark});
  final String? path;

  /// macOS security-scoped bookmark (base64) for [path], captured at pick time.
  /// Always set alongside [path]: a non-null path with its bookmark on connect,
  /// both `null` on disconnect.
  final String? bookmark;
  @override
  List<Object?> get props => [path, bookmark];
}

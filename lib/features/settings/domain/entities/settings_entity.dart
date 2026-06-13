import 'package:equatable/equatable.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/theme/theme_ids.dart';

const Object _unchanged = Object();

class SettingsEntity extends Equatable {
  final int historyLimit;
  final bool saveResponseInHistory;
  final bool isDarkMode;
  final bool isCompactMode;
  final bool isVerticalLayout;
  final double splitRatio;
  final double sideMenuWidth;
  final String themeId;
  final String? activeEnvironmentId;

  // Network configuration (applied to the Dio client at send time).
  final int connectTimeoutMs;
  final int sendTimeoutMs;
  final int receiveTimeoutMs;
  final bool followRedirects;
  final bool verifySsl;
  final String? proxyUrl;

  /// Optional on-disk workspace folder for git-friendly collections (desktop
  /// only; `null` means Hive-only, today's behavior).
  final String? workspacePath;

  const SettingsEntity({
    this.historyLimit = 100,
    this.saveResponseInHistory = false,
    this.isDarkMode = false,
    this.isCompactMode = false,
    this.isVerticalLayout = false,
    this.splitRatio = 0.5,
    this.sideMenuWidth = 300.0,
    this.themeId = kBrutalistThemeId,
    this.activeEnvironmentId,
    this.connectTimeoutMs = 30000,
    this.sendTimeoutMs = 30000,
    this.receiveTimeoutMs = 60000,
    this.followRedirects = true,
    this.verifySsl = true,
    this.proxyUrl,
    this.workspacePath,
  });

  SettingsEntity copyWith({
    int? historyLimit,
    bool? saveResponseInHistory,
    bool? isDarkMode,
    bool? isCompactMode,
    bool? isVerticalLayout,
    double? splitRatio,
    double? sideMenuWidth,
    String? themeId,
    Object? activeEnvironmentId = _unchanged,
    int? connectTimeoutMs,
    int? sendTimeoutMs,
    int? receiveTimeoutMs,
    bool? followRedirects,
    bool? verifySsl,
    Object? proxyUrl = _unchanged,
    Object? workspacePath = _unchanged,
  }) {
    return SettingsEntity(
      historyLimit: historyLimit ?? this.historyLimit,
      saveResponseInHistory: saveResponseInHistory ?? this.saveResponseInHistory,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isCompactMode: isCompactMode ?? this.isCompactMode,
      isVerticalLayout: isVerticalLayout ?? this.isVerticalLayout,
      splitRatio: splitRatio ?? this.splitRatio,
      sideMenuWidth: sideMenuWidth ?? this.sideMenuWidth,
      themeId: themeId ?? this.themeId,
      activeEnvironmentId: identical(activeEnvironmentId, _unchanged)
          ? this.activeEnvironmentId
          : activeEnvironmentId as String?,
      connectTimeoutMs: connectTimeoutMs ?? this.connectTimeoutMs,
      sendTimeoutMs: sendTimeoutMs ?? this.sendTimeoutMs,
      receiveTimeoutMs: receiveTimeoutMs ?? this.receiveTimeoutMs,
      followRedirects: followRedirects ?? this.followRedirects,
      verifySsl: verifySsl ?? this.verifySsl,
      proxyUrl: identical(proxyUrl, _unchanged) ? this.proxyUrl : proxyUrl as String?,
      workspacePath:
          identical(workspacePath, _unchanged) ? this.workspacePath : workspacePath as String?,
    );
  }

  /// Maps the network-related settings to the transport-layer [NetworkConfig].
  NetworkConfig toNetworkConfig() => NetworkConfig(
        connectTimeoutMs: connectTimeoutMs,
        sendTimeoutMs: sendTimeoutMs,
        receiveTimeoutMs: receiveTimeoutMs,
        followRedirects: followRedirects,
        verifySsl: verifySsl,
        proxyUrl: proxyUrl,
      );

  @override
  List<Object?> get props => [
    historyLimit,
    saveResponseInHistory,
    isDarkMode,
    isCompactMode,
    isVerticalLayout,
    splitRatio,
    sideMenuWidth,
    themeId,
    activeEnvironmentId,
    connectTimeoutMs,
    sendTimeoutMs,
    receiveTimeoutMs,
    followRedirects,
    verifySsl,
    proxyUrl,
    workspacePath,
  ];
}

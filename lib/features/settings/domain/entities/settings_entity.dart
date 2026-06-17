import 'package:equatable/equatable.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/theme/theme_ids.dart';

const Object _unchanged = Object();

class SettingsEntity extends Equatable {
  const SettingsEntity({
    this.historyLimit = 100,
    this.saveResponseInHistory = false,
    this.alwaysPrettifyLargeResponses = false,
    this.isDarkMode = false,
    this.isCompactMode = false,
    this.reduceVisualEffects = false,
    this.isVerticalLayout = false,
    this.splitRatio = 0.5,
    this.sideMenuWidth = 300.0,
    this.themeId = kBrutalistThemeId,
    this.activeEnvironmentId,
    this.connectTimeoutMs = 30000,
    this.sendTimeoutMs = 30000,
    this.receiveTimeoutMs = 60000,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.verifySsl = true,
    this.proxyUrl,
    this.clientCertPath,
    this.clientKeyPath,
    this.clientCertPassphrase,
    this.workspacePath,
    this.workspaceBookmark,
    this.responseHistoryLimit = 5,
    this.saveLargeResponsesInHistory = true,
  });
  final int historyLimit;
  final bool saveResponseInHistory;

  /// How many recent responses to keep per tab for time-travel. `0` disables
  /// the feature (no history accumulated, timeline hidden). Clamped on input.
  final int responseHistoryLimit;

  /// When `true` (default), large response bodies are kept in time-travel
  /// history (subject to the 1 MiB on-disk cap). When `false`, history entries
  /// over the large-viewer threshold are stored metadata-only.
  final bool saveLargeResponsesInHistory;

  /// When `true`, response bodies over the large-viewer threshold are
  /// prettified and syntax-highlighted automatically instead of falling back
  /// to the plain-text "large response" viewer. The user opts into the extra
  /// render cost deliberately (default `false`).
  final bool alwaysPrettifyLargeResponses;
  final bool isDarkMode;
  final bool isCompactMode;

  /// When `true`, themes drop expensive effects (backdrop blur, animated
  /// backgrounds) for performance. Default `false` = full effects everywhere.
  final bool reduceVisualEffects;
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

  /// Max redirects to follow when [followRedirects] is on (Dio default: 5).
  final int maxRedirects;
  final bool verifySsl;
  final String? proxyUrl;

  /// Client certificate for mutual TLS (desktop/mobile only; the web build
  /// ignores them). PEM cert + PEM key file paths + optional passphrase. The
  /// passphrase is stored in plaintext in the local settings box, like the
  /// proxy — acceptable for a local-only app.
  final String? clientCertPath;
  final String? clientKeyPath;
  final String? clientCertPassphrase;

  /// Optional on-disk workspace folder for git-friendly collections (desktop
  /// only; `null` means Hive-only, today's behavior).
  final String? workspacePath;

  /// macOS App Sandbox security-scoped bookmark (base64) for [workspacePath].
  /// The folder grant from the open-panel does not survive relaunch, so this
  /// bookmark is what re-authorizes writes on the next launch. `null` on other
  /// platforms / when no workspace is connected.
  final String? workspaceBookmark;

  SettingsEntity copyWith({
    int? historyLimit,
    bool? saveResponseInHistory,
    bool? alwaysPrettifyLargeResponses,
    bool? isDarkMode,
    bool? isCompactMode,
    bool? reduceVisualEffects,
    bool? isVerticalLayout,
    double? splitRatio,
    double? sideMenuWidth,
    String? themeId,
    Object? activeEnvironmentId = _unchanged,
    int? connectTimeoutMs,
    int? sendTimeoutMs,
    int? receiveTimeoutMs,
    bool? followRedirects,
    int? maxRedirects,
    bool? verifySsl,
    Object? proxyUrl = _unchanged,
    Object? clientCertPath = _unchanged,
    Object? clientKeyPath = _unchanged,
    Object? clientCertPassphrase = _unchanged,
    Object? workspacePath = _unchanged,
    Object? workspaceBookmark = _unchanged,
    int? responseHistoryLimit,
    bool? saveLargeResponsesInHistory,
  }) {
    return SettingsEntity(
      historyLimit: historyLimit ?? this.historyLimit,
      saveResponseInHistory:
          saveResponseInHistory ?? this.saveResponseInHistory,
      alwaysPrettifyLargeResponses:
          alwaysPrettifyLargeResponses ?? this.alwaysPrettifyLargeResponses,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isCompactMode: isCompactMode ?? this.isCompactMode,
      reduceVisualEffects: reduceVisualEffects ?? this.reduceVisualEffects,
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
      maxRedirects: maxRedirects ?? this.maxRedirects,
      verifySsl: verifySsl ?? this.verifySsl,
      proxyUrl: identical(proxyUrl, _unchanged)
          ? this.proxyUrl
          : proxyUrl as String?,
      clientCertPath: identical(clientCertPath, _unchanged)
          ? this.clientCertPath
          : clientCertPath as String?,
      clientKeyPath: identical(clientKeyPath, _unchanged)
          ? this.clientKeyPath
          : clientKeyPath as String?,
      clientCertPassphrase: identical(clientCertPassphrase, _unchanged)
          ? this.clientCertPassphrase
          : clientCertPassphrase as String?,
      workspacePath: identical(workspacePath, _unchanged)
          ? this.workspacePath
          : workspacePath as String?,
      workspaceBookmark: identical(workspaceBookmark, _unchanged)
          ? this.workspaceBookmark
          : workspaceBookmark as String?,
      responseHistoryLimit: responseHistoryLimit ?? this.responseHistoryLimit,
      saveLargeResponsesInHistory:
          saveLargeResponsesInHistory ?? this.saveLargeResponsesInHistory,
    );
  }

  /// Maps the network-related settings to the transport-layer [NetworkConfig].
  NetworkConfig toNetworkConfig() => NetworkConfig(
    connectTimeoutMs: connectTimeoutMs,
    sendTimeoutMs: sendTimeoutMs,
    receiveTimeoutMs: receiveTimeoutMs,
    followRedirects: followRedirects,
    maxRedirects: maxRedirects,
    verifySsl: verifySsl,
    proxyUrl: proxyUrl,
    clientCertPath: clientCertPath,
    clientKeyPath: clientKeyPath,
    clientCertPassphrase: clientCertPassphrase,
  );

  @override
  List<Object?> get props => [
    historyLimit,
    saveResponseInHistory,
    alwaysPrettifyLargeResponses,
    isDarkMode,
    isCompactMode,
    reduceVisualEffects,
    isVerticalLayout,
    splitRatio,
    sideMenuWidth,
    themeId,
    activeEnvironmentId,
    connectTimeoutMs,
    sendTimeoutMs,
    receiveTimeoutMs,
    followRedirects,
    maxRedirects,
    verifySsl,
    proxyUrl,
    clientCertPath,
    clientKeyPath,
    clientCertPassphrase,
    workspacePath,
    workspaceBookmark,
    responseHistoryLimit,
    saveLargeResponsesInHistory,
  ];
}

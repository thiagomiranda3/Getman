import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:hive_ce/hive.dart';

part 'settings_model.g.dart';

const Object _unchanged = Object();

@HiveType(typeId: 0)
class SettingsModel extends HiveObject {
  SettingsModel({
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

  factory SettingsModel.fromJson(Map<String, dynamic> json) => SettingsModel(
    historyLimit: json['historyLimit'] as int? ?? 100,
    saveResponseInHistory: json['saveResponseInHistory'] as bool? ?? false,
    alwaysPrettifyLargeResponses:
        json['alwaysPrettifyLargeResponses'] as bool? ?? false,
    isDarkMode: json['isDarkMode'] as bool? ?? false,
    isCompactMode: json['isCompactMode'] as bool? ?? false,
    reduceVisualEffects: json['reduceVisualEffects'] as bool? ?? false,
    isVerticalLayout: json['isVerticalLayout'] as bool? ?? false,
    splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? 0.5,
    sideMenuWidth: (json['sideMenuWidth'] as num?)?.toDouble() ?? 300.0,
    themeId: json['themeId'] as String? ?? kBrutalistThemeId,
    activeEnvironmentId: json['activeEnvironmentId'] as String?,
    connectTimeoutMs: json['connectTimeoutMs'] as int? ?? 30000,
    sendTimeoutMs: json['sendTimeoutMs'] as int? ?? 30000,
    receiveTimeoutMs: json['receiveTimeoutMs'] as int? ?? 60000,
    followRedirects: json['followRedirects'] as bool? ?? true,
    maxRedirects: json['maxRedirects'] as int? ?? 5,
    verifySsl: json['verifySsl'] as bool? ?? true,
    proxyUrl: json['proxyUrl'] as String?,
    clientCertPath: json['clientCertPath'] as String?,
    clientKeyPath: json['clientKeyPath'] as String?,
    clientCertPassphrase: json['clientCertPassphrase'] as String?,
    workspacePath: json['workspacePath'] as String?,
    workspaceBookmark: json['workspaceBookmark'] as String?,
    responseHistoryLimit: json['responseHistoryLimit'] as int? ?? 5,
    saveLargeResponsesInHistory:
        json['saveLargeResponsesInHistory'] as bool? ?? true,
  );

  factory SettingsModel.fromEntity(SettingsEntity entity) => SettingsModel(
    historyLimit: entity.historyLimit,
    saveResponseInHistory: entity.saveResponseInHistory,
    alwaysPrettifyLargeResponses: entity.alwaysPrettifyLargeResponses,
    isDarkMode: entity.isDarkMode,
    isCompactMode: entity.isCompactMode,
    reduceVisualEffects: entity.reduceVisualEffects,
    isVerticalLayout: entity.isVerticalLayout,
    splitRatio: entity.splitRatio,
    sideMenuWidth: entity.sideMenuWidth,
    themeId: entity.themeId,
    activeEnvironmentId: entity.activeEnvironmentId,
    connectTimeoutMs: entity.connectTimeoutMs,
    sendTimeoutMs: entity.sendTimeoutMs,
    receiveTimeoutMs: entity.receiveTimeoutMs,
    followRedirects: entity.followRedirects,
    maxRedirects: entity.maxRedirects,
    verifySsl: entity.verifySsl,
    proxyUrl: entity.proxyUrl,
    clientCertPath: entity.clientCertPath,
    clientKeyPath: entity.clientKeyPath,
    clientCertPassphrase: entity.clientCertPassphrase,
    workspacePath: entity.workspacePath,
    workspaceBookmark: entity.workspaceBookmark,
    responseHistoryLimit: entity.responseHistoryLimit,
    saveLargeResponsesInHistory: entity.saveLargeResponsesInHistory,
  );
  @HiveField(0, defaultValue: 100)
  int historyLimit;

  @HiveField(1, defaultValue: false)
  bool saveResponseInHistory;

  @HiveField(2, defaultValue: false)
  bool isDarkMode;

  @HiveField(3, defaultValue: false)
  bool isCompactMode;

  @HiveField(4, defaultValue: false)
  bool isVerticalLayout;

  @HiveField(5, defaultValue: 0.5)
  double splitRatio;

  @HiveField(6, defaultValue: 300.0)
  double sideMenuWidth;

  @HiveField(7, defaultValue: kBrutalistThemeId)
  String themeId;

  @HiveField(8)
  String? activeEnvironmentId;

  @HiveField(9, defaultValue: 30000)
  int connectTimeoutMs;

  @HiveField(10, defaultValue: 30000)
  int sendTimeoutMs;

  @HiveField(11, defaultValue: 60000)
  int receiveTimeoutMs;

  @HiveField(12, defaultValue: true)
  bool followRedirects;

  @HiveField(13, defaultValue: true)
  bool verifySsl;

  @HiveField(14)
  String? proxyUrl;

  @HiveField(15)
  String? workspacePath;

  @HiveField(16)
  String? workspaceBookmark;

  @HiveField(17, defaultValue: false)
  bool alwaysPrettifyLargeResponses;

  @HiveField(18, defaultValue: 5)
  int maxRedirects;

  @HiveField(19)
  String? clientCertPath;

  @HiveField(20)
  String? clientKeyPath;

  @HiveField(21)
  String? clientCertPassphrase;

  @HiveField(22, defaultValue: false)
  bool reduceVisualEffects;

  @HiveField(23, defaultValue: 5)
  int responseHistoryLimit;

  @HiveField(24, defaultValue: true)
  bool saveLargeResponsesInHistory;

  SettingsModel copyWith({
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
    return SettingsModel(
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

  Map<String, dynamic> toJson() => {
    'historyLimit': historyLimit,
    'saveResponseInHistory': saveResponseInHistory,
    'alwaysPrettifyLargeResponses': alwaysPrettifyLargeResponses,
    'isDarkMode': isDarkMode,
    'isCompactMode': isCompactMode,
    'reduceVisualEffects': reduceVisualEffects,
    'isVerticalLayout': isVerticalLayout,
    'splitRatio': splitRatio,
    'sideMenuWidth': sideMenuWidth,
    'themeId': themeId,
    'activeEnvironmentId': activeEnvironmentId,
    'connectTimeoutMs': connectTimeoutMs,
    'sendTimeoutMs': sendTimeoutMs,
    'receiveTimeoutMs': receiveTimeoutMs,
    'followRedirects': followRedirects,
    'maxRedirects': maxRedirects,
    'verifySsl': verifySsl,
    'proxyUrl': proxyUrl,
    'clientCertPath': clientCertPath,
    'clientKeyPath': clientKeyPath,
    'clientCertPassphrase': clientCertPassphrase,
    'workspacePath': workspacePath,
    'workspaceBookmark': workspaceBookmark,
    'responseHistoryLimit': responseHistoryLimit,
    'saveLargeResponsesInHistory': saveLargeResponsesInHistory,
  };

  SettingsEntity toEntity() => SettingsEntity(
    historyLimit: historyLimit,
    saveResponseInHistory: saveResponseInHistory,
    alwaysPrettifyLargeResponses: alwaysPrettifyLargeResponses,
    isDarkMode: isDarkMode,
    isCompactMode: isCompactMode,
    reduceVisualEffects: reduceVisualEffects,
    isVerticalLayout: isVerticalLayout,
    splitRatio: splitRatio,
    sideMenuWidth: sideMenuWidth,
    themeId: themeId,
    activeEnvironmentId: activeEnvironmentId,
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
    workspacePath: workspacePath,
    workspaceBookmark: workspaceBookmark,
    responseHistoryLimit: responseHistoryLimit,
    saveLargeResponsesInHistory: saveLargeResponsesInHistory,
  );
}

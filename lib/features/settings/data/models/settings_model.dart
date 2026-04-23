import 'package:hive/hive.dart';
import '../../../../core/theme/theme_ids.dart';
import '../../domain/entities/settings_entity.dart';

part 'settings_model.g.dart';

const Object _unchanged = Object();

@HiveType(typeId: 0)
class SettingsModel extends HiveObject {
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

  SettingsModel({
    this.historyLimit = 100,
    this.saveResponseInHistory = false,
    this.isDarkMode = false,
    this.isCompactMode = false,
    this.isVerticalLayout = false,
    this.splitRatio = 0.5,
    this.sideMenuWidth = 300.0,
    this.themeId = kBrutalistThemeId,
    this.activeEnvironmentId,
  });

  SettingsModel copyWith({
    int? historyLimit,
    bool? saveResponseInHistory,
    bool? isDarkMode,
    bool? isCompactMode,
    bool? isVerticalLayout,
    double? splitRatio,
    double? sideMenuWidth,
    String? themeId,
    Object? activeEnvironmentId = _unchanged,
  }) {
    return SettingsModel(
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
    );
  }

  Map<String, dynamic> toJson() => {
    'historyLimit': historyLimit,
    'saveResponseInHistory': saveResponseInHistory,
    'isDarkMode': isDarkMode,
    'isCompactMode': isCompactMode,
    'isVerticalLayout': isVerticalLayout,
    'splitRatio': splitRatio,
    'sideMenuWidth': sideMenuWidth,
    'themeId': themeId,
    'activeEnvironmentId': activeEnvironmentId,
  };

  factory SettingsModel.fromJson(Map<String, dynamic> json) => SettingsModel(
    historyLimit: json['historyLimit'] ?? 100,
    saveResponseInHistory: json['saveResponseInHistory'] ?? false,
    isDarkMode: json['isDarkMode'] ?? false,
    isCompactMode: json['isCompactMode'] ?? false,
    isVerticalLayout: json['isVerticalLayout'] ?? false,
    splitRatio: json['splitRatio'] ?? 0.5,
    sideMenuWidth: (json['sideMenuWidth'] ?? 300.0).toDouble(),
    themeId: json['themeId'] ?? kBrutalistThemeId,
    activeEnvironmentId: json['activeEnvironmentId'] as String?,
  );

  factory SettingsModel.fromEntity(SettingsEntity entity) => SettingsModel(
    historyLimit: entity.historyLimit,
    saveResponseInHistory: entity.saveResponseInHistory,
    isDarkMode: entity.isDarkMode,
    isCompactMode: entity.isCompactMode,
    isVerticalLayout: entity.isVerticalLayout,
    splitRatio: entity.splitRatio,
    sideMenuWidth: entity.sideMenuWidth,
    themeId: entity.themeId,
    activeEnvironmentId: entity.activeEnvironmentId,
  );

  SettingsEntity toEntity() => SettingsEntity(
    historyLimit: historyLimit,
    saveResponseInHistory: saveResponseInHistory,
    isDarkMode: isDarkMode,
    isCompactMode: isCompactMode,
    isVerticalLayout: isVerticalLayout,
    splitRatio: splitRatio,
    sideMenuWidth: sideMenuWidth,
    themeId: themeId,
    activeEnvironmentId: activeEnvironmentId,
  );
}

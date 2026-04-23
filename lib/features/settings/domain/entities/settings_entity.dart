import 'package:equatable/equatable.dart';
import '../../../../core/theme/theme_ids.dart';

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
    );
  }

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
  ];
}

import 'package:hive/hive.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 0)
class SettingsModel extends HiveObject {
  @HiveField(0, defaultValue: 100)
  int historyLimit;

  @HiveField(1, defaultValue: false)
  bool saveResponseInHistory;

  @HiveField(2, defaultValue: false)
  bool isDarkMode;

  SettingsModel({
    this.historyLimit = 100,
    this.saveResponseInHistory = false,
    this.isDarkMode = false,
  });

  SettingsModel copyWith({
    int? historyLimit,
    bool? saveResponseInHistory,
    bool? isDarkMode,
  }) {
    return SettingsModel(
      historyLimit: historyLimit ?? this.historyLimit,
      saveResponseInHistory: saveResponseInHistory ?? this.saveResponseInHistory,
      isDarkMode: isDarkMode ?? this.isDarkMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'historyLimit': historyLimit,
    'saveResponseInHistory': saveResponseInHistory,
    'isDarkMode': isDarkMode,
  };

  factory SettingsModel.fromJson(Map<String, dynamic> json) => SettingsModel(
    historyLimit: json['historyLimit'] ?? 100,
    saveResponseInHistory: json['saveResponseInHistory'] ?? false,
    isDarkMode: json['isDarkMode'] ?? false,
  );
}

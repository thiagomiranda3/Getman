import 'package:hive/hive.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 0)
class SettingsModel extends HiveObject {
  @HiveField(0)
  int historyLimit;

  @HiveField(1)
  bool saveResponseInHistory;

  SettingsModel({
    this.historyLimit = 100,
    this.saveResponseInHistory = false,
  });

  Map<String, dynamic> toJson() => {
    'historyLimit': historyLimit,
    'saveResponseInHistory': saveResponseInHistory,
  };

  factory SettingsModel.fromJson(Map<String, dynamic> json) => SettingsModel(
    historyLimit: json['historyLimit'] ?? 100,
    saveResponseInHistory: json['saveResponseInHistory'] ?? false,
  );
}

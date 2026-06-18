// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsModelAdapter extends TypeAdapter<SettingsModel> {
  @override
  final typeId = 0;

  @override
  SettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettingsModel(
      historyLimit: fields[0] == null ? 100 : (fields[0] as num).toInt(),
      saveResponseInHistory: fields[1] == null ? false : fields[1] as bool,
      alwaysPrettifyLargeResponses: fields[17] == null
          ? false
          : fields[17] as bool,
      isDarkMode: fields[2] == null ? false : fields[2] as bool,
      isCompactMode: fields[3] == null ? false : fields[3] as bool,
      reduceVisualEffects: fields[22] == null ? false : fields[22] as bool,
      isVerticalLayout: fields[4] == null ? false : fields[4] as bool,
      splitRatio: fields[5] == null ? 0.5 : (fields[5] as num).toDouble(),
      sideMenuWidth: fields[6] == null ? 300.0 : (fields[6] as num).toDouble(),
      themeId: fields[7] == null ? 'brutalist' : fields[7] as String,
      activeEnvironmentId: fields[8] as String?,
      connectTimeoutMs: fields[9] == null ? 30000 : (fields[9] as num).toInt(),
      sendTimeoutMs: fields[10] == null ? 30000 : (fields[10] as num).toInt(),
      receiveTimeoutMs: fields[11] == null
          ? 60000
          : (fields[11] as num).toInt(),
      followRedirects: fields[12] == null ? true : fields[12] as bool,
      maxRedirects: fields[18] == null ? 5 : (fields[18] as num).toInt(),
      verifySsl: fields[13] == null ? true : fields[13] as bool,
      proxyUrl: fields[14] as String?,
      clientCertPath: fields[19] as String?,
      clientKeyPath: fields[20] as String?,
      clientCertPassphrase: fields[21] as String?,
      workspacePath: fields[15] as String?,
      workspaceBookmark: fields[16] as String?,
      responseHistoryLimit: fields[23] == null
          ? 5
          : (fields[23] as num).toInt(),
      saveLargeResponsesInHistory: fields[24] == null
          ? true
          : fields[24] as bool,
      checkForUpdatesOnStartup: fields[25] == null ? true : fields[25] as bool,
      skippedUpdateVersion: fields[26] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SettingsModel obj) {
    writer
      ..writeByte(27)
      ..writeByte(0)
      ..write(obj.historyLimit)
      ..writeByte(1)
      ..write(obj.saveResponseInHistory)
      ..writeByte(2)
      ..write(obj.isDarkMode)
      ..writeByte(3)
      ..write(obj.isCompactMode)
      ..writeByte(4)
      ..write(obj.isVerticalLayout)
      ..writeByte(5)
      ..write(obj.splitRatio)
      ..writeByte(6)
      ..write(obj.sideMenuWidth)
      ..writeByte(7)
      ..write(obj.themeId)
      ..writeByte(8)
      ..write(obj.activeEnvironmentId)
      ..writeByte(9)
      ..write(obj.connectTimeoutMs)
      ..writeByte(10)
      ..write(obj.sendTimeoutMs)
      ..writeByte(11)
      ..write(obj.receiveTimeoutMs)
      ..writeByte(12)
      ..write(obj.followRedirects)
      ..writeByte(13)
      ..write(obj.verifySsl)
      ..writeByte(14)
      ..write(obj.proxyUrl)
      ..writeByte(15)
      ..write(obj.workspacePath)
      ..writeByte(16)
      ..write(obj.workspaceBookmark)
      ..writeByte(17)
      ..write(obj.alwaysPrettifyLargeResponses)
      ..writeByte(18)
      ..write(obj.maxRedirects)
      ..writeByte(19)
      ..write(obj.clientCertPath)
      ..writeByte(20)
      ..write(obj.clientKeyPath)
      ..writeByte(21)
      ..write(obj.clientCertPassphrase)
      ..writeByte(22)
      ..write(obj.reduceVisualEffects)
      ..writeByte(23)
      ..write(obj.responseHistoryLimit)
      ..writeByte(24)
      ..write(obj.saveLargeResponsesInHistory)
      ..writeByte(25)
      ..write(obj.checkForUpdatesOnStartup)
      ..writeByte(26)
      ..write(obj.skippedUpdateVersion);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

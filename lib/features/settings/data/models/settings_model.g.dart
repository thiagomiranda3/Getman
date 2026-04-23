// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsModelAdapter extends TypeAdapter<SettingsModel> {
  @override
  final int typeId = 0;

  @override
  SettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettingsModel(
      historyLimit: fields[0] == null ? 100 : fields[0] as int,
      saveResponseInHistory: fields[1] == null ? false : fields[1] as bool,
      isDarkMode: fields[2] == null ? false : fields[2] as bool,
      isCompactMode: fields[3] == null ? false : fields[3] as bool,
      isVerticalLayout: fields[4] == null ? false : fields[4] as bool,
      splitRatio: fields[5] == null ? 0.5 : fields[5] as double,
      sideMenuWidth: fields[6] == null ? 300.0 : fields[6] as double,
      themeId: fields[7] == null ? 'brutalist' : fields[7] as String,
      activeEnvironmentId: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SettingsModel obj) {
    writer
      ..writeByte(9)
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
      ..write(obj.activeEnvironmentId);
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

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_example_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedExampleModelAdapter extends TypeAdapter<SavedExampleModel> {
  @override
  final typeId = 10;

  @override
  SavedExampleModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedExampleModel(
      name: fields[1] as String,
      capturedAtMs: (fields[2] as num).toInt(),
      config: fields[3] as HttpRequestConfig,
      id: fields[0] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SavedExampleModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.capturedAtMs)
      ..writeByte(3)
      ..write(obj.config);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedExampleModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

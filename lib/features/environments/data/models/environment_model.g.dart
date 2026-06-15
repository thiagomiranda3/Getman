// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'environment_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EnvironmentModelAdapter extends TypeAdapter<EnvironmentModel> {
  @override
  final typeId = 4;

  @override
  EnvironmentModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EnvironmentModel(
      name: fields[1] as String,
      id: fields[0] as String?,
      variables: (fields[2] as Map?)?.cast<String, String>(),
      secretKeys: fields[3] == null ? [] : (fields[3] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, EnvironmentModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.variables)
      ..writeByte(3)
      ..write(obj.secretKeys);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvironmentModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

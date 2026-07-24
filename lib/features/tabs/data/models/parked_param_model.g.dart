// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parked_param_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ParkedParamModelAdapter extends TypeAdapter<ParkedParamModel> {
  @override
  final typeId = 13;

  @override
  ParkedParamModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ParkedParamModel(
      key: fields[0] as String,
      value: fields[1] == null ? '' : fields[1] as String,
      rowIndex: fields[2] == null ? 0 : (fields[2] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, ParkedParamModel obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.rowIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParkedParamModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

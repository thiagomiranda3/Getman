// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assertion_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssertionModelAdapter extends TypeAdapter<AssertionModel> {
  @override
  final typeId = 8;

  @override
  AssertionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AssertionModel(
      id: fields[0] as String,
      target: fields[1] == null ? 'statusCode' : fields[1] as String,
      comparator: fields[2] == null ? 'equals' : fields[2] as String,
      path: fields[3] == null ? '' : fields[3] as String,
      expected: fields[4] == null ? '' : fields[4] as String,
      enabled: fields[5] == null ? true : fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AssertionModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.target)
      ..writeByte(2)
      ..write(obj.comparator)
      ..writeByte(3)
      ..write(obj.path)
      ..writeByte(4)
      ..write(obj.expected)
      ..writeByte(5)
      ..write(obj.enabled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssertionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

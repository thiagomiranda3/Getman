// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stored_response_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StoredResponseModelAdapter extends TypeAdapter<StoredResponseModel> {
  @override
  final typeId = 11;

  @override
  StoredResponseModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StoredResponseModel(
      id: fields[0] as String,
      statusCode: (fields[1] as num).toInt(),
      body: fields[2] as String,
      headers: (fields[3] as Map).cast<String, String>(),
      durationMs: (fields[4] as num).toInt(),
      capturedAt: (fields[5] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, StoredResponseModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.statusCode)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(3)
      ..write(obj.headers)
      ..writeByte(4)
      ..write(obj.durationMs)
      ..writeByte(5)
      ..write(obj.capturedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredResponseModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

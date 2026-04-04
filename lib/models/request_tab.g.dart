// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_tab.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HttpRequestTabModelAdapter extends TypeAdapter<HttpRequestTabModel> {
  @override
  final int typeId = 2;

  @override
  HttpRequestTabModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HttpRequestTabModel(
      config: fields[0] as HttpRequestConfig,
      responseBody: fields[1] as String?,
      responseHeaders: (fields[2] as Map?)?.cast<String, String>(),
      statusCode: fields[3] as int?,
      durationMs: fields[4] as int?,
      isSending: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, HttpRequestTabModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.config)
      ..writeByte(1)
      ..write(obj.responseBody)
      ..writeByte(2)
      ..write(obj.responseHeaders)
      ..writeByte(3)
      ..write(obj.statusCode)
      ..writeByte(4)
      ..write(obj.durationMs)
      ..writeByte(5)
      ..write(obj.isSending);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpRequestTabModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

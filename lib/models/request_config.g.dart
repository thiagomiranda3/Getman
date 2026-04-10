// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HttpRequestConfigAdapter extends TypeAdapter<HttpRequestConfig> {
  @override
  final int typeId = 1;

  @override
  HttpRequestConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HttpRequestConfig(
      id: fields[0] as String?,
      method: fields[1] == null ? 'GET' : fields[1] as String,
      url: fields[2] == null ? '' : fields[2] as String,
      headers: (fields[3] as Map?)?.cast<String, String>(),
      params: (fields[4] as Map?)?.cast<String, String>(),
      body: fields[5] == null ? '' : fields[5] as String,
      auth: (fields[6] as Map?)?.cast<String, String>(),
      responseBody: fields[7] as String?,
      responseHeaders: (fields[8] as Map?)?.cast<String, String>(),
      statusCode: fields[9] as int?,
      durationMs: fields[10] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, HttpRequestConfig obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.method)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.headers)
      ..writeByte(4)
      ..write(obj.params)
      ..writeByte(5)
      ..write(obj.body)
      ..writeByte(6)
      ..write(obj.auth)
      ..writeByte(7)
      ..write(obj.responseBody)
      ..writeByte(8)
      ..write(obj.responseHeaders)
      ..writeByte(9)
      ..write(obj.statusCode)
      ..writeByte(10)
      ..write(obj.durationMs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpRequestConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

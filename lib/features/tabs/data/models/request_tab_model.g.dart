// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_tab_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HttpRequestTabModelAdapter extends TypeAdapter<HttpRequestTabModel> {
  @override
  final typeId = 2;

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
      statusCode: (fields[3] as num?)?.toInt(),
      durationMs: (fields[4] as num?)?.toInt(),
      isSending: fields[5] == null ? false : fields[5] as bool,
      collectionNodeId: fields[6] as String?,
      collectionName: fields[7] as String?,
      tabId: fields[8] as String?,
      responseHistory: (fields[9] as List?)?.cast<StoredResponseModel>(),
    );
  }

  @override
  void write(BinaryWriter writer, HttpRequestTabModel obj) {
    writer
      ..writeByte(10)
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
      ..write(obj.isSending)
      ..writeByte(6)
      ..write(obj.collectionNodeId)
      ..writeByte(7)
      ..write(obj.collectionName)
      ..writeByte(8)
      ..write(obj.tabId)
      ..writeByte(9)
      ..write(obj.responseHistory);
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

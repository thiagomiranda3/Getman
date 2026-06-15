// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'multipart_field_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MultipartFieldModelAdapter extends TypeAdapter<MultipartFieldModel> {
  @override
  final typeId = 5;

  @override
  MultipartFieldModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MultipartFieldModel(
      name: fields[0] as String,
      value: fields[1] == null ? '' : fields[1] as String,
      isFile: fields[2] == null ? false : fields[2] as bool,
      filePath: fields[3] as String?,
      contentType: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MultipartFieldModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.isFile)
      ..writeByte(3)
      ..write(obj.filePath)
      ..writeByte(4)
      ..write(obj.contentType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultipartFieldModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

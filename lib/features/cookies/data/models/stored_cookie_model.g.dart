// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stored_cookie_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StoredCookieModelAdapter extends TypeAdapter<StoredCookieModel> {
  @override
  final typeId = 6;

  @override
  StoredCookieModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StoredCookieModel(
      name: fields[0] as String,
      value: fields[1] as String,
      domain: fields[2] as String,
      path: fields[3] == null ? '/' : fields[3] as String,
      secure: fields[4] == null ? false : fields[4] as bool,
      httpOnly: fields[5] == null ? false : fields[5] as bool,
      expiresEpochMs: (fields[6] as num?)?.toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, StoredCookieModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.domain)
      ..writeByte(3)
      ..write(obj.path)
      ..writeByte(4)
      ..write(obj.secure)
      ..writeByte(5)
      ..write(obj.httpOnly)
      ..writeByte(6)
      ..write(obj.expiresEpochMs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredCookieModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

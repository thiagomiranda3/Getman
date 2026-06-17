// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_node_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CollectionNodeAdapter extends TypeAdapter<CollectionNode> {
  @override
  final typeId = 3;

  @override
  CollectionNode read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CollectionNode(
      name: fields[1] as String,
      id: fields[0] as String?,
      isFolder: fields[2] == null ? true : fields[2] as bool,
      children: (fields[3] as List?)?.cast<CollectionNode>(),
      config: fields[4] as HttpRequestConfig?,
      isFavorite: fields[5] == null ? false : fields[5] as bool,
      description: fields[6] as String?,
      examples: (fields[7] as List?)?.cast<SavedExampleModel>(),
      variables: (fields[8] as Map?)?.cast<String, String>(),
      secretKeys: (fields[9] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, CollectionNode obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.isFolder)
      ..writeByte(3)
      ..write(obj.children)
      ..writeByte(4)
      ..write(obj.config)
      ..writeByte(5)
      ..write(obj.isFavorite)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.examples)
      ..writeByte(8)
      ..write(obj.variables)
      ..writeByte(9)
      ..write(obj.secretKeys);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionNodeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

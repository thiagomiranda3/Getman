// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'extraction_rule_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExtractionRuleModelAdapter extends TypeAdapter<ExtractionRuleModel> {
  @override
  final typeId = 7;

  @override
  ExtractionRuleModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExtractionRuleModel(
      id: fields[0] as String,
      kind: fields[1] == null ? 'jsonPath' : fields[1] as String,
      expression: fields[2] == null ? '' : fields[2] as String,
      targetVariable: fields[3] == null ? '' : fields[3] as String,
      enabled: fields[4] == null ? true : fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ExtractionRuleModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kind)
      ..writeByte(2)
      ..write(obj.expression)
      ..writeByte(3)
      ..write(obj.targetVariable)
      ..writeByte(4)
      ..write(obj.enabled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractionRuleModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

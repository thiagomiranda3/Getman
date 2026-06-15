// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_rules_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RequestRulesModelAdapter extends TypeAdapter<RequestRulesModel> {
  @override
  final typeId = 9;

  @override
  RequestRulesModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RequestRulesModel(
      configId: fields[0] as String,
      extractionRules: (fields[1] as List?)?.cast<ExtractionRuleModel>(),
      assertions: (fields[2] as List?)?.cast<AssertionModel>(),
    );
  }

  @override
  void write(BinaryWriter writer, RequestRulesModel obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.configId)
      ..writeByte(1)
      ..write(obj.extractionRules)
      ..writeByte(2)
      ..write(obj.assertions);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RequestRulesModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

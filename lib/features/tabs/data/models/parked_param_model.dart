// Data-layer model for one parked (disabled) query param row: the key/value
// pair removed from the URL plus the row position it re-inserts at when
// re-enabled. Deliberately NOT a HiveObject: the `key` field would shadow
// HiveObjectMixin.key (the box-key getter), and this model is embedded-only
// (nested in HttpRequestConfig), never stored directly in a box.
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart'
    show HttpRequestConfig;
import 'package:hive_ce/hive.dart';

part 'parked_param_model.g.dart';

/// Hive model for a parked (disabled) query param. typeId 13 (first free
/// after 0–12). Nested inside [HttpRequestConfig] (typeId 1, field 16), so
/// it travels with history, collections, and tabs automatically.
@HiveType(typeId: 13)
class ParkedParamModel {
  ParkedParamModel({
    required this.key,
    this.value = '',
    this.rowIndex = 0,
  });

  factory ParkedParamModel.fromEntity(ParkedParamEntity e) =>
      ParkedParamModel(key: e.key, value: e.value, rowIndex: e.rowIndex);

  @HiveField(0)
  String key;

  @HiveField(1, defaultValue: '')
  String value;

  @HiveField(2, defaultValue: 0)
  int rowIndex;

  ParkedParamEntity toEntity() =>
      ParkedParamEntity(key: key, value: value, rowIndex: rowIndex);
}

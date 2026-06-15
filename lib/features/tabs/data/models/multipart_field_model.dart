import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart'
    show HttpRequestConfig;
import 'package:hive_ce/hive.dart';

part 'multipart_field_model.g.dart';

/// Hive model for a single form-body row. typeId 5 (first free after 0–4).
/// Nested inside [HttpRequestConfig] (typeId 1, field 12), so it travels with
/// history, collections, and tabs automatically.
@HiveType(typeId: 5)
class MultipartFieldModel extends HiveObject {
  MultipartFieldModel({
    required this.name,
    this.value = '',
    this.isFile = false,
    this.filePath,
    this.contentType,
  });

  factory MultipartFieldModel.fromEntity(MultipartFieldEntity e) =>
      MultipartFieldModel(
        name: e.name,
        value: e.value,
        isFile: e.isFile,
        filePath: e.filePath,
        contentType: e.contentType,
      );
  @HiveField(0)
  String name;

  @HiveField(1, defaultValue: '')
  String value;

  @HiveField(2, defaultValue: false)
  bool isFile;

  @HiveField(3)
  String? filePath;

  @HiveField(4)
  String? contentType;

  MultipartFieldEntity toEntity() => MultipartFieldEntity(
    name: name,
    value: value,
    isFile: isFile,
    filePath: filePath,
    contentType: contentType,
  );
}

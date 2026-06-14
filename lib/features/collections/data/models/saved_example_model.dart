import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'saved_example_model.g.dart';

/// Hive model for a saved request+response example, embedded in [CollectionNode]
/// via its `examples` field. [config] reuses the existing [HttpRequestConfig]
/// (typeId 1) which already persists the response columns. [capturedAtMs] is
/// epoch millis (no DateTime adapter is registered); reconstructed as UTC.
@HiveType(typeId: 10)
class SavedExampleModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int capturedAtMs;

  @HiveField(3)
  HttpRequestConfig config;

  SavedExampleModel({
    String? id,
    required this.name,
    required this.capturedAtMs,
    required this.config,
  }) : id = id ?? const Uuid().v4();

  factory SavedExampleModel.fromEntity(SavedExampleEntity entity) => SavedExampleModel(
        id: entity.id,
        name: entity.name,
        capturedAtMs: entity.capturedAt.millisecondsSinceEpoch,
        config: HttpRequestConfig.fromEntity(entity.config),
      );

  SavedExampleEntity toEntity() => SavedExampleEntity(
        id: id,
        name: name,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(capturedAtMs, isUtc: true),
        config: config.toEntity(),
      );
}

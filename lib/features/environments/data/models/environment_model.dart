import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'environment_model.g.dart';

@HiveType(typeId: 4)
class EnvironmentModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  Map<String, String> variables;

  /// Names of variables flagged secret. Defaults to empty for pre-existing
  /// environments persisted before this field existed.
  @HiveField(3, defaultValue: <String>[])
  List<String> secretKeys;

  EnvironmentModel({
    String? id,
    required this.name,
    Map<String, String>? variables,
    List<String>? secretKeys,
  })  : id = id ?? const Uuid().v4(),
        variables = variables ?? <String, String>{},
        secretKeys = secretKeys ?? <String>[];

  factory EnvironmentModel.fromEntity(EnvironmentEntity entity) => EnvironmentModel(
        id: entity.id,
        name: entity.name,
        variables: Map<String, String>.from(entity.variables),
        secretKeys: entity.secretKeys.toList(),
      );

  EnvironmentEntity toEntity() => EnvironmentEntity(
        id: id,
        name: name,
        variables: Map<String, String>.unmodifiable(variables),
        secretKeys: Set<String>.unmodifiable(secretKeys),
      );
}

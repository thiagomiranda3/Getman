import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/environment_entity.dart';

part 'environment_model.g.dart';

@HiveType(typeId: 4)
class EnvironmentModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  Map<String, String> variables;

  EnvironmentModel({
    String? id,
    required this.name,
    Map<String, String>? variables,
  })  : id = id ?? const Uuid().v4(),
        variables = variables ?? <String, String>{};

  factory EnvironmentModel.fromEntity(EnvironmentEntity entity) => EnvironmentModel(
        id: entity.id,
        name: entity.name,
        variables: Map<String, String>.from(entity.variables),
      );

  EnvironmentEntity toEntity() => EnvironmentEntity(
        id: id,
        name: name,
        variables: Map<String, String>.unmodifiable(variables),
      );
}

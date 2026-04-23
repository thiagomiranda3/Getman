import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class EnvironmentEntity extends Equatable {
  final String id;
  final String name;
  final Map<String, String> variables;

  EnvironmentEntity({
    String? id,
    required this.name,
    this.variables = const {},
  }) : id = id ?? const Uuid().v4();

  EnvironmentEntity copyWith({
    String? name,
    Map<String, String>? variables,
  }) {
    return EnvironmentEntity(
      id: id,
      name: name ?? this.name,
      variables: variables ?? this.variables,
    );
  }

  @override
  List<Object?> get props => [id, name, variables];
}

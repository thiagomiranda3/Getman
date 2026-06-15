import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class EnvironmentEntity extends Equatable {
  EnvironmentEntity({
    required this.name,
    String? id,
    this.variables = const {},
    this.secretKeys = const {},
  }) : id = id ?? const Uuid().v4();
  final String id;
  final String name;
  final Map<String, String> variables;

  /// Names of variables flagged secret: rendered masked in the editor and
  /// masked on export. Resolution at send time is unaffected.
  final Set<String> secretKeys;

  EnvironmentEntity copyWith({
    String? name,
    Map<String, String>? variables,
    Set<String>? secretKeys,
  }) {
    return EnvironmentEntity(
      id: id,
      name: name ?? this.name,
      variables: variables ?? this.variables,
      secretKeys: secretKeys ?? this.secretKeys,
    );
  }

  @override
  List<Object?> get props => [id, name, variables, secretKeys];
}

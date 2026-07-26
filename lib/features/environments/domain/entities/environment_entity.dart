// Domain entity for an environment: name + a flat variables map + a set of
// secretKeys flagging which variables render masked in the editor/export.

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
  List<Object?> get props => [
    id,
    name,
    variables,
    // Variable ORDER is user-editable (B2 row reorder in the env editor);
    // Equatable's map equality is order-insensitive, so expose the key order
    // or a pure reorder is suppressed as an equal state and the dialog shows
    // the stale order until restart.
    variables.keys.toList(),
    secretKeys,
  ];
}

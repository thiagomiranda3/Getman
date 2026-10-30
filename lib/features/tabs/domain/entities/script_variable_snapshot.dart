// Captured variable layers for one SEND; never reads active settings later.
import 'package:equatable/equatable.dart';

const _unchanged = Object();

class ScriptVariableSnapshot extends Equatable {
  ScriptVariableSnapshot({
    this.environmentId,
    Map<String, String> environmentVariables = const {},
    Map<String, String> collectionVariables = const {},
    Set<String> secretKeys = const {},
  }) : environmentVariables = Map.unmodifiable(environmentVariables),
       collectionVariables = Map.unmodifiable(collectionVariables),
       secretKeys = Set.unmodifiable(secretKeys);
  final String? environmentId;
  final Map<String, String> environmentVariables;
  final Map<String, String> collectionVariables;
  final Set<String> secretKeys;
  Map<String, String> get resolved => {
    ...collectionVariables,
    ...environmentVariables,
  };
  ScriptVariableSnapshot copyWith({
    Object? environmentId = _unchanged,
    Map<String, String>? environmentVariables,
    Map<String, String>? collectionVariables,
    Set<String>? secretKeys,
  }) => ScriptVariableSnapshot(
    environmentId: identical(environmentId, _unchanged)
        ? this.environmentId
        : environmentId as String?,
    environmentVariables: environmentVariables ?? this.environmentVariables,
    collectionVariables: collectionVariables ?? this.collectionVariables,
    secretKeys: secretKeys ?? this.secretKeys,
  );
  @override
  List<Object?> get props => [
    environmentId,
    environmentVariables,
    collectionVariables,
    secretKeys,
  ];
}

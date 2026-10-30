// Immutable ScriptInput value exchanged by script execution components.
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/entities/script_response.dart';

const _unchanged = Object();

class ScriptInput extends Equatable {
  ScriptInput({
    required this.executionId,
    required this.tabId,
    required this.source,
    required this.phase,
    required HttpRequestConfigEntity config,
    this.environmentId,
    Set<String> secretKeys = const {},
    Map<String, String> environmentVariables = const {},
    Map<String, String> collectionVariables = const {},
    Map<String, String> temporaryVariables = const {},
    this.response,
  }) : secretKeys = Set.unmodifiable(secretKeys),
       config = config.copyWith(
         headers: Map.unmodifiable(config.headers),
         auth: Map.unmodifiable(config.auth),
         formFields: List.unmodifiable(config.formFields),
         disabledParams: List.unmodifiable(config.disabledParams),
         disabledHeaderKeys: Set.unmodifiable(config.disabledHeaderKeys),
         responseHeaders: config.responseHeaders == null
             ? null
             : Map<String, String>.unmodifiable(config.responseHeaders!),
       ),
       environmentVariables = Map.unmodifiable(environmentVariables),
       collectionVariables = Map.unmodifiable(collectionVariables),
       temporaryVariables = Map.unmodifiable(temporaryVariables);
  final String executionId;
  final String tabId;
  final String source;
  final ScriptPhase phase;
  final HttpRequestConfigEntity config;
  final String? environmentId;
  final Set<String> secretKeys;
  final Map<String, String> environmentVariables;
  final Map<String, String> collectionVariables;
  final Map<String, String> temporaryVariables;
  final ScriptResponse? response;

  ScriptInput copyWith({
    String? executionId,
    String? tabId,
    String? source,
    ScriptPhase? phase,
    HttpRequestConfigEntity? config,
    Object? environmentId = _unchanged,
    Set<String>? secretKeys,
    Map<String, String>? environmentVariables,
    Map<String, String>? collectionVariables,
    Map<String, String>? temporaryVariables,
    Object? response = _unchanged,
  }) => ScriptInput(
    executionId: executionId ?? this.executionId,
    tabId: tabId ?? this.tabId,
    source: source ?? this.source,
    phase: phase ?? this.phase,
    config: config ?? this.config,
    environmentId: identical(environmentId, _unchanged)
        ? this.environmentId
        : environmentId as String?,
    secretKeys: secretKeys ?? this.secretKeys,
    environmentVariables: environmentVariables ?? this.environmentVariables,
    collectionVariables: collectionVariables ?? this.collectionVariables,
    temporaryVariables: temporaryVariables ?? this.temporaryVariables,
    response: identical(response, _unchanged)
        ? this.response
        : response as ScriptResponse?,
  );
  @override
  List<Object?> get props => [
    executionId,
    tabId,
    source,
    phase,
    config,
    environmentId,
    secretKeys,
    environmentVariables,
    collectionVariables,
    temporaryVariables,
    response,
  ];
}

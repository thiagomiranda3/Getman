// The variable set available to a request field: the active environment
// layered over the request's inherited collection variables (environment
// wins on conflict), plus dynamic built-ins via classify(). Passed to every
// variable-aware field (URL bar, headers, body) for highlighting and
// autocomplete.

import 'package:equatable/equatable.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

/// The full set of variables available to a request field: the active
/// environment layered over the request's inherited collection variables
/// (environment wins on conflict), plus dynamic built-ins via [classify].
/// Pure Dart — the single currency passed to every variable-aware field.
class LayeredVariableContext extends Equatable {
  const LayeredVariableContext({
    this.environmentVariables = const {},
    this.environmentSecrets = const {},
    this.collectionVariables = const {},
    this.collectionSecrets = const {},
    this.environmentName,
  });

  static const LayeredVariableContext empty = LayeredVariableContext();

  final Map<String, String> environmentVariables;
  final Set<String> environmentSecrets;
  final Map<String, String> collectionVariables;
  final Set<String> collectionSecrets;
  final String? environmentName;

  /// Collection overlaid by environment (environment wins). Used for token
  /// highlighting (resolved-vs-not) and as the autocomplete candidate set.
  Map<String, String> get allVariables => {
    ...collectionVariables,
    ...environmentVariables,
  };

  Set<String> get allSecretKeys => {
    ...collectionSecrets,
    ...environmentSecrets,
  };

  bool get isEmpty => allVariables.isEmpty;

  ResolvedVariable classify(String name) =>
      VariableResolutionHelper.classifyLayered(
        name: name,
        collectionVariables: collectionVariables,
        collectionSecrets: collectionSecrets,
        environmentVariables: environmentVariables,
        environmentSecrets: environmentSecrets,
        environmentName: environmentName,
      );

  @override
  List<Object?> get props => [
    environmentVariables,
    environmentSecrets,
    collectionVariables,
    collectionSecrets,
    environmentName,
  ];
}

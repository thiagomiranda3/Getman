// Pure scanner for {{var}} tokens that resolve to NOTHING in the supplied
// variable map — feeds the pre-send warning chip (UnresolvedVarsChip) left
// of SEND. Scans URL, header keys+values, parked disabled params, raw/
// graphql bodies (+ graphqlVariables), and auth values. Reuses
// EnvironmentResolver's token grammar (findVariables) and resolution rules
// (map lookup wins, dynamic built-ins always resolve) — never fork the
// regex or the rules.

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/environment_resolver.dart';

/// Collects the `{{var}}` names a request references that resolve to
/// nothing. Pure Dart. De-duplicated, first-occurrence order; scan order is
/// URL, header keys, header values, parked params (key then value per row),
/// body, graphqlVariables, auth values.
class UnresolvedVariableCollector {
  const UnresolvedVariableCollector._();

  /// Body types whose text fields can carry `{{var}}` tokens. Mirrors which
  /// editors offer variable autocomplete: raw (any text/JSON) and graphql
  /// (query + variables JSON). Form/binary bodies are keyed rows or file
  /// paths — out of scope per the E3 spec.
  static bool _scansBody(BodyType type) =>
      type == BodyType.raw || type == BodyType.graphql;

  static List<String> collect({
    required HttpRequestConfigEntity config,
    required Map<String, String> variables,
  }) {
    final sources = <String>[
      config.url,
      ...config.headers.keys,
      ...config.headers.values,
      for (final param in config.disabledParams) ...[param.key, param.value],
      if (_scansBody(config.bodyType)) config.body,
      if (config.bodyType == BodyType.graphql) config.graphqlVariables,
      ...config.auth.values,
    ];

    final seen = <String>{};
    final unresolved = <String>[];
    for (final source in sources) {
      for (final match in EnvironmentResolver.findVariables(source)) {
        final name = match.name;
        // Same resolution test as the URL highlighter's buildTextSpan.
        if (variables.containsKey(name)) continue;
        if (EnvironmentResolver.isDynamic(name)) continue;
        if (seen.add(name)) unresolved.add(name);
      }
    }
    return unresolved;
  }
}

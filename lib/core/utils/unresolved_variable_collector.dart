// Pure scanner for {{var}} tokens that will ship UNRESOLVED on the wire —
// feeds the pre-send warning chip (UnresolvedVarsChip) left of SEND. Scans
// only what send actually transmits: URL, ENABLED header keys+values
// (disabled rows and parked params never ship), raw/graphql bodies
// (+ graphqlVariables), form-field name+value for urlencoded/multipart
// bodies, and auth values. Header KEYS are never resolved at send, so any
// token there counts as unresolved even when defined. Reuses
// EnvironmentResolver's token grammar (findVariables) and resolution rules
// (map lookup wins, dynamic built-ins always resolve) — never fork the
// regex or the rules.

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/environment_resolver.dart';

/// Collects the `{{var}}` names a request will ship unresolved. Pure Dart.
/// De-duplicated, first-occurrence order; scan order is enabled header keys
/// (always-unresolved — send never resolves keys), then URL, enabled header
/// values, body, graphqlVariables, form fields (name then value per row),
/// auth values.
class UnresolvedVariableCollector {
  const UnresolvedVariableCollector._();

  /// Body types whose `body` text field can carry `{{var}}` tokens: raw (any
  /// text/JSON) and graphql (query text; `graphqlVariables` is scanned
  /// separately). Urlencoded/multipart don't use `body` at all — their
  /// variable-bearing text lives in `formFields` (see [_scansFormFields]
  /// below). Binary's `bodyFilePath` is a file path, never resolved, and
  /// stays out of scope entirely.
  static bool _scansBody(BodyType type) =>
      type == BodyType.raw || type == BodyType.graphql;

  /// Body types whose `formFields` rows can carry `{{var}}` tokens in their
  /// name and/or value — the serializer resolves both at send time
  /// (`RequestSerializer.buildBody`), so a chip that skipped them would miss
  /// a request shipping a literal unresolved `{{var}}`. File rows always
  /// have an empty `value` (see `FormDataEditor`), so scanning them is a
  /// no-op for that half; their `name` is still resolved for multipart.
  static bool _scansFormFields(BodyType type) =>
      type == BodyType.urlencoded || type == BodyType.multipart;

  static List<String> collect({
    required HttpRequestConfigEntity config,
    required Map<String, String> variables,
  }) {
    // Only what actually hits the wire: enabledHeaders (send drops disabled
    // rows first) and NOT disabledParams (parked rows never ship) — warning
    // about a row the request won't send is noise, and staying silent about
    // one it will is a miss.
    final sources = <String>[
      config.url,
      ...config.enabledHeaders.values,
      if (_scansBody(config.bodyType)) config.body,
      if (config.bodyType == BodyType.graphql) config.graphqlVariables,
      if (_scansFormFields(config.bodyType))
        for (final field in config.formFields) ...[field.name, field.value],
      ...config.auth.values,
    ];

    final seen = <String>{};
    final unresolved = <String>[];
    // Header KEYS are deliberately never resolved at send (resolveMap covers
    // values only — see environments-and-chaining.md), so ANY {{var}} in an
    // enabled header key ships as a literal, RFC-invalid header name — it is
    // unresolved on the wire even when the name is defined in the env.
    for (final key in config.enabledHeaders.keys) {
      for (final match in EnvironmentResolver.findVariables(key)) {
        if (seen.add(match.name)) unresolved.add(match.name);
      }
    }
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

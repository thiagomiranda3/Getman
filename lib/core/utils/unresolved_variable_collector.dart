// Pure scanner for {{var}} tokens that resolve to NOTHING in the supplied
// variable map — feeds the pre-send warning chip (UnresolvedVarsChip) left
// of SEND. Scans URL, header keys+values, parked disabled params, raw/
// graphql bodies (+ graphqlVariables), form-field name+value for
// urlencoded/multipart bodies, and auth values. Reuses EnvironmentResolver's
// token grammar (findVariables) and resolution rules (map lookup wins,
// dynamic built-ins always resolve) — never fork the regex or the rules.

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/environment_resolver.dart';

/// Collects the `{{var}}` names a request references that resolve to
/// nothing. Pure Dart. De-duplicated, first-occurrence order; scan order is
/// URL, header keys, header values, parked params (key then value per row),
/// body, graphqlVariables, form fields (name then value per row), auth
/// values.
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
    final sources = <String>[
      config.url,
      ...config.headers.keys,
      ...config.headers.values,
      for (final param in config.disabledParams) ...[param.key, param.value],
      if (_scansBody(config.bodyType)) config.body,
      if (config.bodyType == BodyType.graphql) config.graphqlVariables,
      if (_scansFormFields(config.bodyType))
        for (final field in config.formFields) ...[field.name, field.value],
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

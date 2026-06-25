import 'package:getman/core/utils/environment_resolver.dart';

/// Recursively resolves `{{var}}` (and dynamic `{{$...}}`) tokens in a single
/// JSON argument [value] against [vars]. Only `String` leaves are substituted;
/// `Map`/`List` are walked; all other types pass through unchanged. Resolving
/// per-value (not over the raw JSON text) keeps the document structurally valid
/// even when a substituted value contains quotes or braces.
dynamic resolveMcpArgValue(dynamic value, Map<String, String> vars) {
  if (value is String) return EnvironmentResolver.resolve(value, vars);
  if (value is Map<String, dynamic>) {
    return value.map((k, v) => MapEntry(k, resolveMcpArgValue(v, vars)));
  }
  if (value is List<dynamic>) {
    return value.map((e) => resolveMcpArgValue(e, vars)).toList();
  }
  return value;
}

/// Resolves `{{var}}` tokens in every value of an MCP tool-call [arguments]
/// object. See [resolveMcpArgValue] for the per-value rules.
Map<String, dynamic> resolveMcpArguments(
  Map<String, dynamic> arguments,
  Map<String, String> vars,
) => arguments.map((k, v) => MapEntry(k, resolveMcpArgValue(v, vars)));

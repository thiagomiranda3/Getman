import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/environment_resolver.dart';

/// Data-layer helper that turns a request's auth + body configuration into the
/// concrete headers / query / payload handed to [NetworkService]. Lives in the
/// data layer because it deals with wire concerns (base64, form encoding, Dio
/// `FormData`); the domain entity stays pure.
///
/// Auth/body credential values are resolved through [EnvironmentResolver] here,
/// at send time only — history records the templated (unresolved) config, so
/// this must never feed back into anything persisted.
class RequestSerializer {
  RequestSerializer._();

  /// Injects auth into [headers] / [query] (both mutated in place). Existing
  /// explicit `Authorization` / api-key headers are respected (skip-if-set) so
  /// a hand-written header always wins over the AUTH tab.
  ///
  /// [AuthType.inherit] is treated as a no-op here; parent-collection auth is
  /// resolved upstream at dispatch time before reaching the send pipeline.
  static void injectAuth({
    required AuthConfig auth,
    required Map<String, String> headers,
    required Map<String, List<String>> query,
    required Map<String, String> envVars,
  }) {
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        return;
      case AuthType.bearer:
        if (_hasHeader(headers, 'authorization')) return;
        final token = EnvironmentResolver.resolve(auth.token, envVars);
        if (token.isEmpty) return;
        headers['Authorization'] = 'Bearer $token';
      case AuthType.basic:
        if (_hasHeader(headers, 'authorization')) return;
        final user = EnvironmentResolver.resolve(auth.username, envVars);
        final pass = EnvironmentResolver.resolve(auth.password, envVars);
        final encoded = base64.encode(utf8.encode('$user:$pass'));
        headers['Authorization'] = 'Basic $encoded';
      case AuthType.apiKey:
        final name = EnvironmentResolver.resolve(auth.apiKeyName, envVars);
        if (name.isEmpty) return;
        final value = EnvironmentResolver.resolve(auth.apiKeyValue, envVars);
        if (auth.apiKeyLocation == ApiKeyLocation.header) {
          if (_hasHeader(headers, name)) return;
          headers[name] = value;
        } else {
          query.putIfAbsent(name, () => <String>[]).add(value);
        }
    }
  }

  static bool _hasHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    return headers.keys.any((k) => k.toLowerCase() == lower);
  }
}

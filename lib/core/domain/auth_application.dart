// Computes the concrete effect (AuthApplication: headers + optional query
// param) an AuthConfig has on an outgoing request, independent of how it is
// applied. Shared by the send-path serializer (adds to Dio headers/query)
// and the code-gen service (adds headers, appends to the URL string) so the
// per-AuthType decision doesn't drift between the two callers.

import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/header_utils.dart';

/// The concrete effect an [AuthConfig] has on an outgoing request, computed
/// independently of *how* it is applied.
///
/// The send-path serializer adds [headers] to its header map and [queryParam]
/// (if any) to its Dio query map; the code-gen service adds [headers] and
/// appends [queryParam] to the URL string. Centralizing the per-[AuthType]
/// decision here stops those two callers from drifting and gives a future
/// OAuth2 type a single place to grow into.
class AuthApplication {
  const AuthApplication({this.headers = const {}, this.queryParam});

  /// Header(s) to add. Already respects "an explicit header wins": empty when
  /// the relevant header is already set or the credential is blank.
  final Map<String, String> headers;

  /// An api-key credential destined for the query string, or null. The key and
  /// value are resolved but NOT URL-encoded — a caller targeting a URL string
  /// must encode them (the Dio query map encodes on its own). Already respects
  /// "an explicit param wins": null when [resolveAuthApplication]'s
  /// `hasQueryParam` reports the name as already present.
  final MapEntry<String, String>? queryParam;

  static const AuthApplication none = AuthApplication();
}

/// Computes the [AuthApplication] for [auth] against the request's
/// [currentHeaders]. Credential values pass through [resolve] first — the send
/// path injects an environment resolver; code-gen passes the identity so
/// `{{vars}}` stay templated.
///
/// [hasQueryParam] is the query-string mirror of the header skip-if-set check:
/// it must report whether the request already carries a query param with the
/// given (resolved) name, so an api-key with `addTo: query` never appends a
/// second, conflicting credential next to a hand-written one. Query-param
/// names are case-sensitive (unlike headers) — report an exact-name match.
AuthApplication resolveAuthApplication({
  required AuthConfig auth,
  required Map<String, String> currentHeaders,
  required String Function(String value) resolve,
  required bool Function(String name) hasQueryParam,
}) {
  switch (auth.type) {
    case AuthType.none:
    case AuthType.inherit:
      return AuthApplication.none;
    case AuthType.bearer:
      if (HeaderUtils.hasHeader(currentHeaders, 'authorization')) {
        return AuthApplication.none;
      }
      final token = resolve(auth.token);
      if (token.isEmpty) return AuthApplication.none;
      return AuthApplication(headers: {'Authorization': 'Bearer $token'});
    case AuthType.basic:
      if (HeaderUtils.hasHeader(currentHeaders, 'authorization')) {
        return AuthApplication.none;
      }
      final user = resolve(auth.username);
      final pass = resolve(auth.password);
      // Don't emit `Basic <base64(':')>` for blank credentials (matches the
      // bearer/api-key empty guards). A username-only basic auth is still valid.
      if (user.isEmpty && pass.isEmpty) return AuthApplication.none;
      final encoded = base64.encode(utf8.encode('$user:$pass'));
      return AuthApplication(headers: {'Authorization': 'Basic $encoded'});
    case AuthType.apiKey:
      final name = resolve(auth.apiKeyName);
      if (name.isEmpty) return AuthApplication.none;
      final value = resolve(auth.apiKeyValue);
      if (auth.apiKeyLocation == ApiKeyLocation.header) {
        if (HeaderUtils.hasHeader(currentHeaders, name)) {
          return AuthApplication.none;
        }
        return AuthApplication(headers: {name: value});
      }
      // Query mirror of the header skip-if-set: a hand-written same-name
      // param wins over the AUTH tab (appending would ship two conflicting
      // credentials: `?api_key=OVERRIDE&api_key=<authValue>`).
      if (hasQueryParam(name)) return AuthApplication.none;
      return AuthApplication(queryParam: MapEntry(name, value));
  }
}

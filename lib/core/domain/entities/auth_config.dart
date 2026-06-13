import 'package:equatable/equatable.dart';

/// Authentication scheme for a request. Persisted as a discriminator string in
/// the raw `auth` map carried by [HttpRequestConfigEntity] (Hive field 6).
enum AuthType {
  none('none'),
  inherit('inherit'),
  bearer('bearer'),
  basic('basic'),
  apiKey('apikey');

  final String wire;
  const AuthType(this.wire);

  static AuthType fromWire(String? value) {
    for (final t in AuthType.values) {
      if (t.wire == value) return t;
    }
    return AuthType.none;
  }
}

/// Where an API-key credential is placed on the outgoing request.
enum ApiKeyLocation {
  header('header'),
  query('query');

  final String wire;
  const ApiKeyLocation(this.wire);

  static ApiKeyLocation fromWire(String? value) =>
      value == 'query' ? ApiKeyLocation.query : ApiKeyLocation.header;
}

/// Type-safe view over the raw `Map<String, String> auth` stored on a request
/// config. The entity keeps storing the raw map (so the Hive model and field 6
/// are untouched — no migration); this value object is the ergonomic currency
/// at the UI and send-pipeline call sites.
///
/// An empty map decodes to [AuthType.none], so every pre-existing record (whose
/// `auth` defaulted to `{}`) reads back as "No auth" with zero migration.
class AuthConfig extends Equatable {
  final AuthType type;
  final String token; // bearer
  final String username; // basic
  final String password; // basic
  final String apiKeyName; // apiKey
  final String apiKeyValue; // apiKey
  final ApiKeyLocation apiKeyLocation; // apiKey

  const AuthConfig({
    this.type = AuthType.none,
    this.token = '',
    this.username = '',
    this.password = '',
    this.apiKeyName = '',
    this.apiKeyValue = '',
    this.apiKeyLocation = ApiKeyLocation.header,
  });

  static const AuthConfig none = AuthConfig();

  factory AuthConfig.fromMap(Map<String, String> map) {
    if (map.isEmpty) return none;
    return AuthConfig(
      type: AuthType.fromWire(map['type']),
      token: map['token'] ?? '',
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      apiKeyName: map['key'] ?? '',
      apiKeyValue: map['value'] ?? '',
      apiKeyLocation: ApiKeyLocation.fromWire(map['addTo']),
    );
  }

  /// Serializes back to the raw map persisted on the entity. Returns an empty
  /// map for [AuthType.none] so persisted records stay tidy and dedup-stable.
  Map<String, String> toMap() {
    switch (type) {
      case AuthType.none:
        return const {};
      case AuthType.inherit:
        return const {'type': 'inherit'};
      case AuthType.bearer:
        return {'type': 'bearer', 'token': token};
      case AuthType.basic:
        return {'type': 'basic', 'username': username, 'password': password};
      case AuthType.apiKey:
        return {
          'type': 'apikey',
          'key': apiKeyName,
          'value': apiKeyValue,
          'addTo': apiKeyLocation.wire,
        };
    }
  }

  AuthConfig copyWith({
    AuthType? type,
    String? token,
    String? username,
    String? password,
    String? apiKeyName,
    String? apiKeyValue,
    ApiKeyLocation? apiKeyLocation,
  }) {
    return AuthConfig(
      type: type ?? this.type,
      token: token ?? this.token,
      username: username ?? this.username,
      password: password ?? this.password,
      apiKeyName: apiKeyName ?? this.apiKeyName,
      apiKeyValue: apiKeyValue ?? this.apiKeyValue,
      apiKeyLocation: apiKeyLocation ?? this.apiKeyLocation,
    );
  }

  @override
  List<Object?> get props => [
        type,
        token,
        username,
        password,
        apiKeyName,
        apiKeyValue,
        apiKeyLocation,
      ];
}

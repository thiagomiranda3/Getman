// Maps a NormalizedSecurityScheme (from an OpenAPI/Swagger import) to a
// Getman AuthConfig: shape only, secret values always left blank. Returns
// the scheme's suggested secret env-var name to seed (bearerToken/
// basicPassword/apiKey) and a human warning for oauth2/unsupported schemes,
// which map to AuthConfig.none.

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

/// Maps a normalized security scheme to a Getman [AuthConfig] (type/shape only,
/// secret values blank) plus an optional secret env-var name to seed and an
/// optional human warning. See plan "Design decisions locked in" #1.
NormalizedAuth mapAuth(NormalizedSecurityScheme? scheme) {
  if (scheme == null) {
    return const NormalizedAuth(config: AuthConfig.none);
  }
  switch (scheme.kind) {
    case SecuritySchemeKind.bearer:
      return const NormalizedAuth(
        config: AuthConfig(type: AuthType.bearer),
        secretVarName: 'bearerToken',
      );
    case SecuritySchemeKind.basic:
      return const NormalizedAuth(
        config: AuthConfig(type: AuthType.basic),
        secretVarName: 'basicPassword',
      );
    case SecuritySchemeKind.apiKeyHeader:
      return NormalizedAuth(
        config: AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: scheme.apiKeyName ?? '',
        ),
        secretVarName: 'apiKey',
      );
    case SecuritySchemeKind.apiKeyQuery:
      return NormalizedAuth(
        config: AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: scheme.apiKeyName ?? '',
          apiKeyLocation: ApiKeyLocation.query,
        ),
        secretVarName: 'apiKey',
      );
    case SecuritySchemeKind.oauth2:
      return const NormalizedAuth(
        config: AuthConfig.none,
        warning:
            'OAuth2 security is not yet wired — auth left as None. '
            'Set credentials manually once OAuth2 support lands.',
      );
    case SecuritySchemeKind.unsupported:
      return const NormalizedAuth(
        config: AuthConfig.none,
        warning: 'Unsupported security scheme — auth left as None.',
      );
  }
}

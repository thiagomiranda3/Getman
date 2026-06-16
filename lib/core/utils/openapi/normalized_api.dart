// lib/core/utils/openapi/normalized_api.dart
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

/// A version-agnostic view of an OpenAPI 3.x / Swagger 2.0 spec.
class NormalizedApi extends Equatable {
  const NormalizedApi({
    required this.title,
    this.servers = const [],
    this.operations = const [],
  });

  final String title;
  final List<NormalizedServer> servers;
  final List<NormalizedOperation> operations;

  @override
  List<Object?> get props => [title, servers, operations];
}

class NormalizedServer extends Equatable {
  const NormalizedServer({
    required this.url,
    this.description,
    this.variables = const {},
  });

  /// May contain `{var}` server-variable templates.
  final String url;
  final String? description;

  /// Server-variable name → default value.
  final Map<String, String> variables;

  @override
  List<Object?> get props => [url, description, variables];
}

class NormalizedParam extends Equatable {
  const NormalizedParam({required this.name, this.value = ''});
  final String name;
  final String value;

  @override
  List<Object?> get props => [name, value];
}

class NormalizedBody extends Equatable {
  const NormalizedBody({
    required this.bodyType,
    this.raw = '',
    this.contentType,
    this.formFields = const [],
  });

  final BodyType bodyType;
  final String raw;
  final String? contentType;
  final List<MultipartFieldEntity> formFields;

  @override
  List<Object?> get props => [bodyType, raw, contentType, formFields];
}

enum SecuritySchemeKind {
  bearer,
  basic,
  apiKeyHeader,
  apiKeyQuery,
  oauth2,
  unsupported,
}

class NormalizedSecurityScheme extends Equatable {
  const NormalizedSecurityScheme({required this.kind, this.apiKeyName});
  final SecuritySchemeKind kind;

  /// The header/query parameter name for `apiKey` schemes.
  final String? apiKeyName;

  @override
  List<Object?> get props => [kind, apiKeyName];
}

class NormalizedOperation extends Equatable {
  const NormalizedOperation({
    required this.method,
    required this.path,
    required this.name,
    this.tag,
    this.queryParams = const [],
    this.headerParams = const [],
    this.body,
    this.security,
    this.warnings = const [],
  });

  final String method;

  /// Original path with `{param}` templates (e.g. `/users/{id}`).
  final String path;
  final String name;
  final String? tag;
  final List<NormalizedParam> queryParams;
  final List<NormalizedParam> headerParams;
  final NormalizedBody? body;
  final NormalizedSecurityScheme? security;
  final List<String> warnings;

  @override
  List<Object?> get props => [
    method,
    path,
    name,
    tag,
    queryParams,
    headerParams,
    body,
    security,
    warnings,
  ];
}

/// The mapped auth for one operation: a Getman [AuthConfig] plus an optional
/// secret env-var name to seed (empty) into every created environment, plus an
/// optional human warning (e.g. unsupported OAuth2).
class NormalizedAuth extends Equatable {
  const NormalizedAuth({
    required this.config,
    this.secretVarName,
    this.warning,
  });
  final AuthConfig config;
  final String? secretVarName;
  final String? warning;

  @override
  List<Object?> get props => [config, secretVarName, warning];
}

/// The product of an import: a single collection [root] node, the
/// [environments] to create, and any non-fatal [warnings] to surface.
class ImportResult extends Equatable {
  const ImportResult({
    required this.root,
    this.environments = const [],
    this.warnings = const [],
  });

  final CollectionNodeEntity root;
  final List<EnvironmentEntity> environments;
  final List<String> warnings;

  @override
  List<Object?> get props => [root, environments, warnings];
}

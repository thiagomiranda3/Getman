// Format-agnostic API-doc entities (ApiDoc/ApiServer/ApiParam/ApiBody/
// ApiResponse/ApiOperation) built by CollectionToApiDoc from a collection
// subtree, then rendered by OpenApiSerializer and MarkdownDocSerializer.
// ApiOperation.security carries auth SHAPE only — never token/password/key
// values.

import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';

/// A format-agnostic description of an API, built from a collection subtree.
/// Both `OpenApiSerializer` and `MarkdownDocSerializer` consume this.
class ApiDoc extends Equatable {
  const ApiDoc({
    required this.title,
    this.version = '1.0.0',
    this.servers = const [],
    this.operations = const [],
    this.warnings = const [],
  });

  final String title;
  final String version;
  final List<ApiServer> servers;
  final List<ApiOperation> operations;
  final List<String> warnings;

  @override
  List<Object?> get props => [title, version, servers, operations, warnings];
}

class ApiServer extends Equatable {
  const ApiServer({required this.url, this.variables = const {}});

  /// May contain `{var}` templates for unresolved server variables.
  final String url;

  /// Server-variable name → default value (empty for unknown/secret).
  final Map<String, String> variables;

  @override
  List<Object?> get props => [url, variables];
}

class ApiParam extends Equatable {
  const ApiParam({
    required this.name,
    this.example,
    this.isRequired = false,
    this.schema,
  });

  final String name;
  final String? example;
  final bool isRequired;
  final JsonSchema? schema;

  @override
  List<Object?> get props => [name, example, isRequired, schema];
}

class ApiBody extends Equatable {
  const ApiBody({required this.contentType, this.schema, this.example});

  final String contentType;
  final JsonSchema? schema;

  /// The verbatim sample payload (decoded JSON value or a raw string).
  final Object? example;

  @override
  List<Object?> get props => [contentType, schema, example];
}

class ApiResponse extends Equatable {
  const ApiResponse({
    required this.statusCode,
    this.description = '',
    this.body,
  });

  final int statusCode;
  final String description;
  final ApiBody? body;

  @override
  List<Object?> get props => [statusCode, description, body];
}

class ApiOperation extends Equatable {
  const ApiOperation({
    required this.method,
    required this.path,
    required this.summary,
    this.description,
    this.tag,
    this.queryParams = const [],
    this.headerParams = const [],
    this.pathParams = const [],
    this.requestBody,
    this.responses = const [],
    this.security = AuthConfig.none,
  });

  final String method; // upper-case, e.g. GET
  final String path; // OpenAPI path with `{var}` templates, e.g. /users/{id}
  final String summary;
  final String? description;
  final String? tag;
  final List<ApiParam> queryParams;
  final List<ApiParam> headerParams;
  final List<ApiParam> pathParams;
  final ApiBody? requestBody;
  final List<ApiResponse> responses;

  /// Auth shape only — serializers read `type`/`apiKeyName`/`apiKeyLocation`
  /// and NEVER emit token/password/value.
  final AuthConfig security;

  @override
  List<Object?> get props => [
    method,
    path,
    summary,
    description,
    tag,
    queryParams,
    headerParams,
    pathParams,
    requestBody,
    responses,
    security,
  ];
}

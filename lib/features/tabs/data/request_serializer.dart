import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:getman/core/domain/auth_application.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/network/network_service.dart' show NetworkService;
import 'package:getman/core/utils/body_type_utils.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/core/utils/io/file_reader.dart';
import 'package:getman/core/utils/path_utils.dart';

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
    final app = resolveAuthApplication(
      auth: auth,
      currentHeaders: headers,
      resolve: (value) => EnvironmentResolver.resolve(value, envVars),
    );
    headers.addAll(app.headers);
    final queryParam = app.queryParam;
    if (queryParam != null) {
      query.putIfAbsent(queryParam.key, () => <String>[]).add(queryParam.value);
    }
  }

  /// Builds the request payload from [config]'s body type, resolving `{{vars}}`
  /// and mutating [headers]' Content-Type to match the chosen body type:
  /// - urlencoded → forces `application/x-www-form-urlencoded`;
  /// - multipart → strips Content-Type so Dio sets it with a boundary;
  /// - binary → `application/octet-stream` unless a non-default type is set;
  /// - raw → untouched (the user owns the Content-Type);
  /// - none → null body, untouched headers.
  ///
  /// Returns the value to hand to Dio as `data` (String / Map / FormData /
  /// bytes / null). File-backed rows are read via the platform file reader
  /// (throws on web — file bodies are desktop/mobile only). Async so the file
  /// reads happen off the UI isolate — a large upload never stalls the app
  /// while the request is assembled.
  static Future<dynamic> buildBody({
    required HttpRequestConfigEntity config,
    required Map<String, String> headers,
    required Map<String, String> envVars,
  }) async {
    String r(String v) => EnvironmentResolver.resolve(v, envVars);

    switch (config.bodyType) {
      case BodyType.none:
        return null;
      case BodyType.raw:
        return config.body.isEmpty ? null : r(config.body);
      case BodyType.urlencoded:
        BodyTypeUtils.applyContentType(headers, BodyType.urlencoded);
        return <String, String>{
          for (final f in config.formFields)
            if (!f.isFile && f.name.isNotEmpty) r(f.name): r(f.value),
        };
      case BodyType.multipart:
        // Dio adds it with the boundary.
        BodyTypeUtils.applyContentType(headers, BodyType.multipart);
        final form = FormData();
        for (final f in config.formFields) {
          if (f.name.isEmpty) continue;
          final name = r(f.name);
          if (f.isFile) {
            final path = f.filePath;
            if (path == null || path.isEmpty) continue;
            form.files.add(
              MapEntry(
                name,
                MultipartFile.fromBytes(
                  await _readBytes(path),
                  filename: _basename(path),
                  contentType: _parseMediaType(f.contentType),
                ),
              ),
            );
          } else {
            form.fields.add(MapEntry(name, r(f.value)));
          }
        }
        return form;
      case BodyType.binary:
        final path = config.bodyFilePath;
        if (path == null || path.isEmpty) return null;
        BodyTypeUtils.applyContentType(headers, BodyType.binary);
        return _readBytes(path);
      case BodyType.graphql:
        BodyTypeUtils.applyContentType(headers, BodyType.graphql);
        final varsText = r(config.graphqlVariables).trim();
        Object? variables;
        if (varsText.isEmpty) {
          variables = const <String, dynamic>{};
        } else {
          try {
            variables = jsonDecode(varsText);
          } on FormatException catch (e) {
            throw GraphqlVariablesException(e.message);
          }
        }
        return <String, dynamic>{
          'query': r(config.body),
          'variables': variables,
        };
    }
  }

  /// Reads the file at [path], translating any read failure (missing/deleted
  /// file, unsupported on web) into a pure [FileBodyException] carrying the
  /// path. The repository maps that to a NetworkFailure so a missing upload
  /// surfaces as a visible error response instead of an uncaught throw.
  static Future<List<int>> _readBytes(String path) async {
    try {
      return await readFileBytes(path);
    } catch (e) {
      throw FileBodyException(path, cause: e);
    }
  }

  static String _basename(String path) => PathUtils.basename(path);

  /// Parses a per-row content type into a [DioMediaType], or null when unset or
  /// malformed (so a bad value falls back to Dio's default rather than throwing
  /// mid-send).
  static DioMediaType? _parseMediaType(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      return DioMediaType.parse(value.trim());
    } on Object catch (_) {
      return null;
    }
  }
}

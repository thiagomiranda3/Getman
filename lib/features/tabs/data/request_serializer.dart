import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/core/utils/io/file_reader.dart';

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
        _setHeader(headers, 'Content-Type', 'application/x-www-form-urlencoded');
        return <String, String>{
          for (final f in config.formFields)
            if (!f.isFile && f.name.isNotEmpty) r(f.name): r(f.value),
        };
      case BodyType.multipart:
        _removeHeader(headers, 'content-type'); // Dio adds it with the boundary.
        final form = FormData();
        for (final f in config.formFields) {
          if (f.name.isEmpty) continue;
          final name = r(f.name);
          if (f.isFile) {
            final path = f.filePath;
            if (path == null || path.isEmpty) continue;
            form.files.add(MapEntry(
              name,
              MultipartFile.fromBytes(await readFileBytes(path), filename: _basename(path)),
            ));
          } else {
            form.fields.add(MapEntry(name, r(f.value)));
          }
        }
        return form;
      case BodyType.binary:
        final path = config.bodyFilePath;
        if (path == null || path.isEmpty) return null;
        if (!_hasCustomContentType(headers)) {
          _setHeader(headers, 'Content-Type', 'application/octet-stream');
        }
        return await readFileBytes(path);
    }
  }

  static bool _hasHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    return headers.keys.any((k) => k.toLowerCase() == lower);
  }

  /// Sets [name] to [value], dropping any case-variant of the key first so we
  /// never emit both `Content-Type` and `content-type`.
  static void _setHeader(Map<String, String> headers, String name, String value) {
    _removeHeader(headers, name);
    headers[name] = value;
  }

  static void _removeHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    headers.removeWhere((k, _) => k.toLowerCase() == lower);
  }

  /// True when a Content-Type is present that isn't the app's JSON default —
  /// i.e. the user deliberately chose one, which a binary body should keep.
  static bool _hasCustomContentType(Map<String, String> headers) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'content-type') {
        return e.value.trim().toLowerCase() != 'application/json';
      }
    }
    return false;
  }

  static String _basename(String path) => path.split(RegExp(r'[/\\]')).last;
}

import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';

/// Target language for generated request code.
enum CodeGenTarget {
  curl('cURL'),
  jsFetch('JavaScript — fetch'),
  pythonRequests('Python — requests');

  final String label;
  const CodeGenTarget(this.label);
}

/// Generates copy-pasteable request snippets from a request config. Output is a
/// *template*: `{{env vars}}` are left verbatim (never resolved) so the user
/// can paste and substitute. Reflects auth (bearer/basic/api-key) and the
/// chosen body type. Pure — depends only on core/domain.
class CodeGenService {
  CodeGenService._();

  static String generate(HttpRequestConfigEntity config, CodeGenTarget target) {
    final eff = _effective(config);
    switch (target) {
      case CodeGenTarget.curl:
        return _curl(eff);
      case CodeGenTarget.jsFetch:
        return _fetch(eff);
      case CodeGenTarget.pythonRequests:
        return _python(eff);
    }
  }

  // ---- effective request (auth applied, content-type adjusted) ----

  static _Effective _effective(HttpRequestConfigEntity config) {
    final headers = Map<String, String>.of(config.headers);
    var url = config.url;

    final auth = config.authConfig;
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        break;
      case AuthType.bearer:
        if (auth.token.isNotEmpty && !_hasKey(headers, 'authorization')) {
          headers['Authorization'] = 'Bearer ${auth.token}';
        }
      case AuthType.basic:
        if (!_hasKey(headers, 'authorization')) {
          final encoded = base64.encode(utf8.encode('${auth.username}:${auth.password}'));
          headers['Authorization'] = 'Basic $encoded';
        }
      case AuthType.apiKey:
        if (auth.apiKeyName.isNotEmpty) {
          if (auth.apiKeyLocation == ApiKeyLocation.header) {
            if (!_hasKey(headers, auth.apiKeyName)) headers[auth.apiKeyName] = auth.apiKeyValue;
          } else {
            final sep = url.contains('?') ? '&' : '?';
            url += '$sep${auth.apiKeyName}=${auth.apiKeyValue}';
          }
        }
    }

    // Mirror the send pipeline's content-type handling for structured bodies.
    switch (config.bodyType) {
      case BodyType.urlencoded:
        _setKey(headers, 'Content-Type', 'application/x-www-form-urlencoded');
      case BodyType.multipart:
        _removeKey(headers, 'content-type');
      case BodyType.binary:
        if (!_hasCustomContentType(headers)) {
          _setKey(headers, 'Content-Type', 'application/octet-stream');
        }
      case BodyType.none:
      case BodyType.raw:
        break;
    }

    return _Effective(
      method: config.method,
      url: url,
      headers: headers,
      bodyType: config.bodyType,
      rawBody: config.body,
      formFields: config.formFields,
      binaryPath: config.bodyFilePath,
    );
  }

  // ---- cURL ----

  static String _curl(_Effective e) {
    final b = StringBuffer('curl --request ${e.method} \\\n');
    b.write("  --url '${e.url}'");
    e.headers.forEach((k, v) {
      b.write(" \\\n  --header '$k: ${_sq(v)}'");
    });
    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) b.write(" \\\n  --data '${_sq(e.rawBody)}'");
      case BodyType.urlencoded:
        b.write(" \\\n  --data '${_sq(_urlEncodedString(e.formFields))}'");
      case BodyType.multipart:
        for (final f in e.formFields) {
          if (f.name.isEmpty) continue;
          final v = f.isFile ? '@${f.filePath ?? ''}' : f.value;
          b.write(" \\\n  --form '${_sq('${f.name}=$v')}'");
        }
      case BodyType.binary:
        b.write(" \\\n  --data-binary '@${e.binaryPath ?? ''}'");
    }
    return b.toString();
  }

  // ---- JS fetch ----

  static String _fetch(_Effective e) {
    final b = StringBuffer();
    final opts = StringBuffer();
    opts.write("  method: '${e.method}',\n");
    if (e.headers.isNotEmpty) {
      opts.write('  headers: {\n');
      e.headers.forEach((k, v) => opts.write("    '$k': '${_sq(v)}',\n"));
      opts.write('  },\n');
    }
    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) opts.write('  body: ${_jsString(e.rawBody)},\n');
      case BodyType.urlencoded:
        opts.write('  body: new URLSearchParams(${_jsObject(e.formFields)}),\n');
      case BodyType.multipart:
        b.write('const form = new FormData();\n');
        for (final f in e.formFields) {
          if (f.name.isEmpty) continue;
          if (f.isFile) {
            b.write("// form.append('${f.name}', /* File for ${f.filePath ?? ''} */);\n");
          } else {
            b.write("form.append('${f.name}', '${_sq(f.value)}');\n");
          }
        }
        opts.write('  body: form,\n');
      case BodyType.binary:
        b.write('// Attach the file at ${e.binaryPath ?? ''} as the request body.\n');
    }
    b.write("fetch('${e.url}', {\n");
    b.write(opts.toString());
    b.write('});');
    return b.toString();
  }

  // ---- Python requests ----

  static String _python(_Effective e) {
    final b = StringBuffer('import requests\n\n');
    b.write("url = '${e.url}'\n");
    b.write('headers = {\n');
    e.headers.forEach((k, v) => b.write("    '$k': '${_sq(v)}',\n"));
    b.write('}\n');

    final extra = <String>['headers=headers'];
    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) {
          b.write('data = ${_pyString(e.rawBody)}\n');
          extra.add('data=data');
        }
      case BodyType.urlencoded:
        b.write('data = ${_pyObject(e.formFields)}\n');
        extra.add('data=data');
      case BodyType.multipart:
        b.write('files = {\n');
        for (final f in e.formFields) {
          if (f.name.isEmpty) continue;
          if (f.isFile) {
            b.write("    '${f.name}': open('${f.filePath ?? ''}', 'rb'),\n");
          } else {
            b.write("    '${f.name}': (None, '${f.value}'),\n");
          }
        }
        b.write('}\n');
        extra.add('files=files');
      case BodyType.binary:
        b.write("data = open('${e.binaryPath ?? ''}', 'rb')\n");
        extra.add('data=data');
    }

    b.write("\nresponse = requests.request('${e.method}', url, ${extra.join(', ')})\n");
    b.write('print(response.text)');
    return b.toString();
  }

  // ---- helpers ----

  static String _urlEncodedString(List<MultipartFieldEntity> fields) {
    return [
      for (final f in fields)
        if (!f.isFile && f.name.isNotEmpty) '${f.name}=${f.value}',
    ].join('&');
  }

  static String _jsObject(List<MultipartFieldEntity> fields) {
    final entries = [
      for (final f in fields)
        if (!f.isFile && f.name.isNotEmpty) "'${f.name}': '${_sq(f.value)}'",
    ];
    return '{ ${entries.join(', ')} }';
  }

  static String _pyObject(List<MultipartFieldEntity> fields) {
    final entries = [
      for (final f in fields)
        if (!f.isFile && f.name.isNotEmpty) "'${f.name}': '${f.value}'",
    ];
    return '{${entries.join(', ')}}';
  }

  /// Escapes single quotes for embedding inside a `'...'` literal (shell/JS/py).
  static String _sq(String v) => v.replaceAll('\n', '\\n').replaceAll("'", "\\'");

  /// Quotes a JS string with backticks when it spans lines, else single quotes.
  static String _jsString(String v) =>
      v.contains('\n') ? '`$v`' : "'${v.replaceAll("'", "\\'")}'";

  /// Python: triple-quote multiline payloads, else single-quote.
  static String _pyString(String v) =>
      v.contains('\n') ? "'''$v'''" : "'${v.replaceAll("'", "\\'")}'";

  static bool _hasKey(Map<String, String> h, String name) {
    final l = name.toLowerCase();
    return h.keys.any((k) => k.toLowerCase() == l);
  }

  static void _setKey(Map<String, String> h, String name, String value) {
    _removeKey(h, name);
    h[name] = value;
  }

  static void _removeKey(Map<String, String> h, String name) {
    final l = name.toLowerCase();
    h.removeWhere((k, _) => k.toLowerCase() == l);
  }

  static bool _hasCustomContentType(Map<String, String> h) {
    for (final e in h.entries) {
      if (e.key.toLowerCase() == 'content-type') {
        return e.value.trim().toLowerCase() != 'application/json';
      }
    }
    return false;
  }
}

class _Effective {
  final String method;
  final String url;
  final Map<String, String> headers;
  final BodyType bodyType;
  final String rawBody;
  final List<MultipartFieldEntity> formFields;
  final String? binaryPath;

  _Effective({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyType,
    required this.rawBody,
    required this.formFields,
    required this.binaryPath,
  });
}

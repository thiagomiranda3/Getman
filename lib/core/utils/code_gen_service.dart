import 'dart:convert';

import 'package:getman/core/domain/auth_application.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/header_utils.dart';

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

    // Code-gen emits a template: pass the identity resolver so `{{vars}}` stay
    // verbatim. Same auth decision as the send path (auth_application.dart).
    final auth = resolveAuthApplication(
      auth: config.authConfig,
      currentHeaders: headers,
      resolve: (value) => value,
    );
    headers.addAll(auth.headers);
    final apiKeyQuery = auth.queryParam;
    if (apiKeyQuery != null) {
      final sep = url.contains('?') ? '&' : '?';
      final name = Uri.encodeComponent(apiKeyQuery.key);
      final value = Uri.encodeComponent(apiKeyQuery.value);
      url += '$sep$name=$value';
    }

    // Mirror the send pipeline's content-type handling for structured bodies.
    switch (config.bodyType) {
      case BodyType.urlencoded:
        HeaderUtils.setHeader(headers, 'Content-Type', 'application/x-www-form-urlencoded');
      case BodyType.multipart:
        HeaderUtils.removeHeader(headers, 'content-type');
      case BodyType.binary:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          HeaderUtils.setHeader(headers, 'Content-Type', 'application/octet-stream');
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
      b.write(" \\\n  --header '$k: ${_shellSq(v)}'");
    });
    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) b.write(" \\\n  --data '${_shellSq(e.rawBody)}'");
      case BodyType.urlencoded:
        b.write(" \\\n  --data '${_shellSq(_urlEncodedString(e.formFields))}'");
      case BodyType.multipart:
        for (final f in e.formFields) {
          if (f.name.isEmpty) continue;
          final v = f.isFile ? '@${f.filePath ?? ''}' : f.value;
          b.write(" \\\n  --form '${_shellSq('${f.name}=$v')}'");
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

  /// Escapes a value for embedding inside a `'...'` literal in JS/Python
  /// (backslash first so it isn't double-processed, then newline, then quote).
  static String _sq(String v) =>
      v.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll("'", "\\'");

  /// POSIX single-quote escaping for shell (curl): a literal `'` becomes the
  /// `'\''` idiom (close, escaped quote, reopen). Newlines are literal inside
  /// single quotes, so they're left as-is.
  static String _shellSq(String v) => v.replaceAll("'", "'\\''");

  /// A JS string literal. Multiline payloads use a JSON-encoded double-quoted
  /// literal (so embedded backticks / `\${...}` can't form a template literal);
  /// single-line uses a simple single-quoted literal.
  static String _jsString(String v) => v.contains('\n') ? jsonEncode(v) : "'${_sq(v)}'";

  /// A Python string literal. Multiline payloads use a JSON-encoded
  /// double-quoted literal (valid Python — so an embedded `'''` can't break
  /// it); single-line uses a simple single-quoted literal.
  static String _pyString(String v) => v.contains('\n') ? jsonEncode(v) : "'${_sq(v)}'";

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

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
  nodeAxios('Node.js — axios'),
  pythonRequests('Python — requests'),
  goNetHttp('Go — net/http'),
  javaOkHttp('Java — OkHttp')
  ;

  const CodeGenTarget(this.label);

  final String label;
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
      case CodeGenTarget.nodeAxios:
        return _nodeAxios(eff);
      case CodeGenTarget.pythonRequests:
        return _python(eff);
      case CodeGenTarget.goNetHttp:
        return _goNetHttp(eff);
      case CodeGenTarget.javaOkHttp:
        return _javaOkHttp(eff);
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
        HeaderUtils.setHeader(
          headers,
          'Content-Type',
          'application/x-www-form-urlencoded',
        );
      case BodyType.multipart:
        HeaderUtils.removeHeader(headers, 'content-type');
      case BodyType.binary:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          HeaderUtils.setHeader(
            headers,
            'Content-Type',
            'application/octet-stream',
          );
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
    final b = StringBuffer('curl --request ${e.method} \\\n')
      ..write("  --url '${e.url}'");
    e.headers.forEach((k, v) {
      b.write(" \\\n  --header '$k: ${_shellSq(v)}'");
    });
    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) {
          b.write(" \\\n  --data '${_shellSq(e.rawBody)}'");
        }
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
    final opts = StringBuffer()..write("  method: '${e.method}',\n");
    if (e.headers.isNotEmpty) {
      opts.write('  headers: {\n');
      e.headers.forEach((k, v) => opts.write("    '$k': '${_sq(v)}',\n"));
      opts.write('  },\n');
    }
    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) {
          opts.write('  body: ${_jsString(e.rawBody)},\n');
        }
      case BodyType.urlencoded:
        opts.write(
          '  body: new URLSearchParams(${_jsObject(e.formFields)}),\n',
        );
      case BodyType.multipart:
        b.write('const form = new FormData();\n');
        for (final f in e.formFields) {
          if (f.name.isEmpty) continue;
          if (f.isFile) {
            b.write(
              "// form.append('${f.name}', /* File for ${f.filePath ?? ''} */);\n",
            );
          } else {
            b.write("form.append('${f.name}', '${_sq(f.value)}');\n");
          }
        }
        opts.write('  body: form,\n');
      case BodyType.binary:
        b.write(
          '// Attach the file at ${e.binaryPath ?? ''} as the request body.\n',
        );
    }
    b
      ..write("fetch('${e.url}', {\n")
      ..write(opts.toString())
      ..write('});');
    return b.toString();
  }

  // ---- Python requests ----

  static String _python(_Effective e) {
    final b = StringBuffer('import requests\n\n')
      ..write("url = '${e.url}'\n")
      ..write('headers = {\n');
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

    b
      ..write(
        '\nresponse = '
        "requests.request('${e.method}', url, ${extra.join(', ')})\n",
      )
      ..write('print(response.text)');
    return b.toString();
  }

  // ---- Node.js axios ----

  static String _nodeAxios(_Effective e) {
    final pre = StringBuffer();
    final opts = StringBuffer()
      ..write("  method: '${e.method}',\n")
      ..write("  url: '${e.url}',\n");

    final isMultipart = e.bodyType == BodyType.multipart;
    if (e.headers.isNotEmpty || isMultipart) {
      opts.write('  headers: {\n');
      e.headers.forEach((k, v) => opts.write("    '$k': '${_sq(v)}',\n"));
      // form.getHeaders() carries the multipart boundary content-type.
      if (isMultipart) opts.write('    ...form.getHeaders(),\n');
      opts.write('  },\n');
    }

    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) {
          opts.write('  data: ${_jsString(e.rawBody)},\n');
        }
      case BodyType.urlencoded:
        opts.write(
          '  data: new URLSearchParams(${_jsObject(e.formFields)}),\n',
        );
      case BodyType.multipart:
        opts.write('  data: form,\n');
      case BodyType.binary:
        break;
    }

    if (isMultipart) {
      pre
        ..write("const FormData = require('form-data');\n")
        ..write('const form = new FormData();\n');
      for (final f in e.formFields) {
        if (f.name.isEmpty) continue;
        if (f.isFile) {
          pre.write(
            "// form.append('${f.name}', fs.createReadStream('${f.filePath ?? ''}'));\n",
          );
        } else {
          pre.write("form.append('${f.name}', '${_sq(f.value)}');\n");
        }
      }
    } else if (e.bodyType == BodyType.binary) {
      pre.write(
        '// Read the file at ${e.binaryPath ?? ''} (e.g. fs.readFileSync) and set it as `data`.\n',
      );
    }

    final b = StringBuffer("const axios = require('axios');\n");
    if (pre.isNotEmpty) {
      b
        ..write('\n')
        ..write(pre.toString());
    }
    b
      ..write('\nconst options = {\n')
      ..write(opts.toString())
      ..write('};\n\n')
      ..write('axios.request(options)\n')
      ..write('  .then((res) => console.log(res.data))\n')
      ..write('  .catch((err) => console.error(err));');
    return b.toString();
  }

  // ---- Go net/http ----

  static String _goNetHttp(_Effective e) {
    final imports = <String>{'fmt', 'io', 'net/http'};
    final body = StringBuffer();
    final comments = StringBuffer();
    var reqBodyArg = 'nil';

    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) {
          imports.add('strings');
          body.write(
            '\tpayload := strings.NewReader(${_dqString(e.rawBody)})\n',
          );
          reqBodyArg = 'payload';
        }
      case BodyType.urlencoded:
        imports.add('strings');
        final encoded = _dqString(_urlEncodedString(e.formFields));
        body.write('\tpayload := strings.NewReader($encoded)\n');
        reqBodyArg = 'payload';
      case BodyType.multipart:
        comments.write(
          '\t// Build a multipart/form-data body with mime/multipart.Writer (omitted).\n',
        );
      case BodyType.binary:
        comments.write(
          '\t// Open the file at ${e.binaryPath ?? ''} and pass it as the request body.\n',
        );
    }

    final b = StringBuffer('package main\n\n')..write('import (\n');
    for (final i in imports.toList()..sort()) {
      b.write('\t"$i"\n');
    }
    b
      ..write(')\n\n')
      ..write('func main() {\n')
      ..write('\turl := ${_dqString(e.url)}\n')
      ..write('\tmethod := "${e.method}"\n\n');
    if (body.isNotEmpty) {
      b
        ..write(body.toString())
        ..write('\n');
    }
    if (comments.isNotEmpty) b.write(comments.toString());
    b
      ..write('\tclient := &http.Client{}\n')
      ..write('\treq, err := http.NewRequest(method, url, $reqBodyArg)\n')
      ..write('\tif err != nil {\n\t\tpanic(err)\n\t}\n');
    e.headers.forEach((k, v) {
      b.write('\treq.Header.Add(${_dqString(k)}, ${_dqString(v)})\n');
    });
    b
      ..write('\n\tres, err := client.Do(req)\n')
      ..write('\tif err != nil {\n\t\tpanic(err)\n\t}\n')
      ..write('\tdefer res.Body.Close()\n\n')
      ..write('\tbody, _ := io.ReadAll(res.Body)\n')
      ..write('\tfmt.Println(string(body))\n')
      ..write('}');
    return b.toString();
  }

  // ---- Java OkHttp ----

  static String _javaOkHttp(_Effective e) {
    final b = StringBuffer('OkHttpClient client = new OkHttpClient();\n\n');
    var bodyExpr = 'null';

    switch (e.bodyType) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (e.rawBody.isNotEmpty) {
          final ct = _contentTypeOf(e.headers, 'application/json');
          final rawLiteral = _dqString(e.rawBody);
          b
            ..write(
              'MediaType mediaType = MediaType.parse(${_dqString(ct)});\n',
            )
            ..write(
              'RequestBody body = '
              'RequestBody.create($rawLiteral, mediaType);\n\n',
            );
          bodyExpr = 'body';
        }
      case BodyType.urlencoded:
        b.write('RequestBody body = new FormBody.Builder()\n');
        for (final f in e.formFields) {
          if (f.isFile || f.name.isEmpty) continue;
          b.write('  .add(${_dqString(f.name)}, ${_dqString(f.value)})\n');
        }
        b.write('  .build();\n\n');
        bodyExpr = 'body';
      case BodyType.multipart:
        b.write(
          'RequestBody body = '
          'new MultipartBody.Builder().setType(MultipartBody.FORM)\n',
        );
        for (final f in e.formFields) {
          if (f.name.isEmpty) continue;
          if (f.isFile) {
            b.write(
              '  // .addFormDataPart(${_dqString(f.name)}, "${f.filePath ?? ''}", '
              'RequestBody.create(new File("${f.filePath ?? ''}"), null))\n',
            );
          } else {
            b.write(
              '  .addFormDataPart('
              '${_dqString(f.name)}, ${_dqString(f.value)})\n',
            );
          }
        }
        b.write('  .build();\n\n');
        bodyExpr = 'body';
      case BodyType.binary:
        b.write(
          '// Read the file at ${e.binaryPath ?? ''} into a RequestBody '
          '(RequestBody.create(new File(...), mediaType)).\n',
        );
        b.write('RequestBody body = null;\n\n');
        bodyExpr = 'body';
    }

    // The body/mediaType carries the content-type for any non-empty body, so
    // skip a redundant (and for multipart, boundary-less) Content-Type header.
    final skipContentType = e.bodyType != BodyType.none;

    b
      ..write('Request request = new Request.Builder()\n')
      ..write('  .url(${_dqString(e.url)})\n')
      ..write('  .method("${e.method}", $bodyExpr)\n');
    e.headers.forEach((k, v) {
      if (skipContentType && k.toLowerCase() == 'content-type') return;
      b.write('  .addHeader(${_dqString(k)}, ${_dqString(v)})\n');
    });
    b
      ..write('  .build();\n\n')
      ..write('Response response = client.newCall(request).execute();\n')
      ..write('System.out.println(response.body().string());');
    return b.toString();
  }

  // ---- helpers ----

  static String _contentTypeOf(Map<String, String> headers, String fallback) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') return entry.value;
    }
    return fallback;
  }

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
      v.replaceAll(r'\', r'\\').replaceAll('\n', r'\n').replaceAll("'", r"\'");

  /// POSIX single-quote escaping for shell (curl): a literal `'` becomes the
  /// `'\''` idiom (close, escaped quote, reopen). Newlines are literal inside
  /// single quotes, so they're left as-is.
  static String _shellSq(String v) => v.replaceAll("'", r"'\''");

  /// A JS string literal. Multiline payloads use a JSON-encoded double-quoted
  /// literal (so embedded backticks / `\${...}` can't form a template literal);
  /// single-line uses a simple single-quoted literal.
  static String _jsString(String v) =>
      v.contains('\n') ? jsonEncode(v) : "'${_sq(v)}'";

  /// A Python string literal. Multiline payloads use a JSON-encoded
  /// double-quoted literal (valid Python — so an embedded `'''` can't break
  /// it); single-line uses a simple single-quoted literal.
  static String _pyString(String v) =>
      v.contains('\n') ? jsonEncode(v) : "'${_sq(v)}'";

  /// A double-quoted string literal valid in Go and Java. Multiline payloads
  /// use a JSON-encoded literal (its escapes are a compatible subset);
  /// single-line uses a simple double-quoted literal.
  static String _dqString(String v) =>
      v.contains('\n') ? jsonEncode(v) : '"${_dq(v)}"';

  /// Escapes a value for embedding inside a `"..."` literal (backslash first,
  /// then newline, then the double quote).
  static String _dq(String v) =>
      v.replaceAll(r'\', r'\\').replaceAll('\n', r'\n').replaceAll('"', r'\"');
}

class _Effective {
  _Effective({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyType,
    required this.rawBody,
    required this.formFields,
    required this.binaryPath,
  });
  final String method;
  final String url;
  final Map<String, String> headers;
  final BodyType bodyType;
  final String rawBody;
  final List<MultipartFieldEntity> formFields;
  final String? binaryPath;
}

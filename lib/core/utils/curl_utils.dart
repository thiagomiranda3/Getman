// Full cURL command PARSER: tokenizes a pasted `curl ...` string (handling
// shell/ANSI-C/double quoting and `\`-newline line continuations), reads its
// flags (-X/-H/-d/--data-raw/--data-urlencode/-F/-u/-b/-G/-T/...), and
// resolves the method + body type into an HttpRequestConfigEntity. Powers
// the URL bar's curl-paste shortcut (see url_bar.dart's `_handleUrlChanged`).
//
// Gotchas: method/body-type are INFERRED when -X/--request isn't given
// (HEAD if -I, GET if -G, PUT if -T/--upload-file, POST if any -d/-F data,
// else GET); -d/--data/--data-binary honor a leading `@file` reference while
// --data-raw explicitly does not (matches curl's own semantics).
// `generate()` at the bottom of this file is a one-line delegate to
// CodeGenService.generate(..., CodeGenTarget.curl) — the actual curl-string
// FORMATTING lives there, not here, so parse and generate are not
// symmetric code paths.

import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_methods.dart';
import 'package:getman/core/utils/code_gen_service.dart';

class CurlUtils {
  /// Value-taking flags we don't model. Their argument is consumed and
  /// discarded so it isn't mistaken for the URL (e.g. `-o <file> <url>`).
  static const _skipValueFlags = {
    '-o',
    '--output',
    '-x',
    '--proxy',
    '-m',
    '--max-time',
    '--connect-timeout',
    '-T',
    '--upload-file',
    '--cert',
    '--key',
    '--cacert',
    '-w',
    '--write-out',
    '--retry',
    '--limit-rate',
    '--resolve',
    '--ciphers',
  };

  /// Splits an argument into (flag, inlineValue): a long flag's `=value`
  /// (`--header=X: y`), or a short flag's glued value (`-XPOST`,
  /// `-HAccept: json`, `-dbody`) — only for value-taking short flags, so
  /// boolean bundles like `-sS` stay untouched. Plain tokens pass through
  /// with a null inline value.
  static (String, String?) _splitFlag(String raw) {
    if (raw.startsWith('--') && raw.contains('=')) {
      final eq = raw.indexOf('=');
      return (raw.substring(0, eq), raw.substring(eq + 1));
    }
    if (raw.length > 2 &&
        raw.startsWith('-') &&
        !raw.startsWith('--') &&
        _gluedShortFlags.contains(raw[1])) {
      return (raw.substring(0, 2), raw.substring(2));
    }
    return (raw, null);
  }

  /// Single-letter value-taking flags that curl accepts with a glued argument
  /// (`-XPOST`). Letters of modeled flags plus `o`/`x`/`m`/`w` (skip-flags) so
  /// `-omyfile` doesn't leak its value into URL detection.
  static const _gluedShortFlags = {
    'X',
    'H',
    'd',
    'A',
    'e',
    'b',
    'u',
    'F',
    'T',
    'o',
    'x',
    'm',
    'w',
  };

  static final RegExp _domainish = RegExp(r'^[\w.-]+\.[\w.-]+');
  static final RegExp _hostPort = RegExp(r'^[\w.-]+:\d+');

  /// Parses a curl command into an [HttpRequestConfigEntity]. Returns null only
  /// when [curl] clearly isn't a curl invocation or carries no URL. Never
  /// throws — unknown flags are tolerated.
  static HttpRequestConfigEntity? parse(String curl, {required String id}) {
    // Tokenize first; the first token tells us whether this really is a curl
    // invocation. The tokenizer handles leading whitespace, shell quoting, and
    // `\`-newline line continuations.
    final args = _tokenize(curl);
    if (args.isEmpty || args[0].toLowerCase() != 'curl') {
      return null;
    }

    var explicitMethod = false;
    String? method;
    var url = '';
    final headers = <String, String>{};
    final dataParts = <String>[];
    var hasData = false; // any -d/--data* flag seen (drives POST inference)
    // True if any data came via --data-urlencode: the user already chose the
    // encoding, so keep it a raw body rather than re-splitting into form rows.
    var urlencodeData = false;
    var forceGet = false;
    var headRequest = false;
    var uploadFile = false; // -T/--upload-file (PUT inference)

    final formFields = <MultipartFieldEntity>[];
    var hasForm = false;

    String? bodyFilePath; // set by `--data-binary @file`
    var auth = const <String, String>{};

    void addData(String data, {bool allowFileRef = false}) {
      hasData = true;
      // A leading `@` is a file reference for the data flags that support it
      // (-d/--data/--data-ascii and --data-binary). --data-raw explicitly
      // does NOT: curl's manual says it posts data without the special `@`
      // interpretation.
      if (allowFileRef && data.startsWith('@')) {
        bodyFilePath = data.substring(1);
        return;
      }
      dataParts.add(data);
    }

    for (var i = 1; i < args.length; i++) {
      final raw = args[i];

      // Split a long flag's inline value: `--header=X: y` ->
      // (`--header`, `X: y`).
      final (flag, inlineValue) = _splitFlag(raw);

      // Reads the value for a value-taking flag: the inline `=value` if
      // present, else the next token. Returns null if neither exists.
      String? takeValue() {
        if (inlineValue != null) return inlineValue;
        if (i + 1 < args.length) return args[++i];
        return null;
      }

      if (flag == '-X' || flag == '--request') {
        final v = takeValue();
        if (v != null) {
          method = v.toUpperCase();
          explicitMethod = true;
        }
      } else if (flag == '-H' || flag == '--header') {
        final v = takeValue();
        if (v != null) _addHeader(headers, v);
      } else if (flag == '-d' ||
          flag == '--data' ||
          flag == '--data-ascii' ||
          flag == '--data-binary') {
        // A leading `@` is a file reference curl reads from disk. Only
        // --data-raw (below) disables that interpretation.
        final v = takeValue();
        if (v != null) addData(v, allowFileRef: true);
      } else if (flag == '--data-raw') {
        // curl disables `@`-file interpretation for --data-raw: the value
        // always posts as literal data.
        final v = takeValue();
        if (v != null) addData(v);
      } else if (flag == '--data-urlencode') {
        final v = takeValue();
        if (v != null) {
          urlencodeData = true;
          addData(_urlEncodeData(v));
        }
      } else if (flag == '-F' || flag == '--form') {
        final v = takeValue();
        if (v != null) {
          hasForm = true;
          final field = _parseFormField(v);
          if (field != null) formFields.add(field);
        }
      } else if (flag == '-u' || flag == '--user') {
        final v = takeValue();
        if (v != null) auth = _basicAuthFromUserArg(v);
      } else if (flag == '-A' || flag == '--user-agent') {
        final v = takeValue();
        if (v != null) headers.putIfAbsent('User-Agent', () => v);
      } else if (flag == '-e' || flag == '--referer') {
        final v = takeValue();
        if (v != null) headers.putIfAbsent('Referer', () => v);
      } else if (flag == '-b' || flag == '--cookie') {
        final v = takeValue();
        // curl treats `-b name=val` (containing `=`) as a cookie; a value with
        // no `=` is a cookie *file*, which we can't read — fold both into the
        // Cookie header anyway (best effort) only when it looks like a pair.
        if (v != null && v.contains('=') && !_hasHeader(headers, 'cookie')) {
          headers['Cookie'] = v;
        }
      } else if (flag == '-G' || flag == '--get') {
        forceGet = true;
      } else if (flag == '-I' || flag == '--head') {
        headRequest = true;
      } else if (flag == '-T') {
        // -T <file>: upload (PUT). Best effort: capture as a binary body.
        final v = takeValue();
        if (v != null) {
          uploadFile = true;
          bodyFilePath = v;
        }
      } else if (flag == '--upload-file') {
        final v = takeValue();
        if (v != null) {
          uploadFile = true;
          bodyFilePath = v;
        }
      } else if (flag == '--url') {
        final v = takeValue();
        if (v != null && url.isEmpty) url = v;
      } else if (_skipValueFlags.contains(flag)) {
        takeValue(); // consume + discard the unmodeled value
      } else if (flag.startsWith('-')) {
        // Unknown flag. If it carried an inline `=value`, it's fully consumed.
        // Otherwise treat it as a boolean flag and ignore it (don't swallow the
        // next token — it might be the URL).
      } else if (url.isEmpty && _looksLikeUrl(raw)) {
        url = raw;
      }
    }

    // ---- Method inference (when -X/--request was not given) ----
    if (!explicitMethod) {
      if (headRequest) {
        method = 'HEAD';
      } else if (forceGet) {
        method = 'GET';
      } else if (uploadFile) {
        method = 'PUT';
      } else if (hasData || hasForm) {
        method = 'POST';
      } else {
        method = 'GET';
      }
    }
    method ??= 'GET';
    method = _clampMethod(method);

    // ---- Body assembly ----
    // curl concatenates plain -d/--data values with '&'.
    var body = dataParts.join('&');

    // -G turns accumulated data into the query string.
    if (forceGet && body.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url$sep$body';
      body = '';
      dataParts.clear();
      hasData = false;
    }

    if (url.isEmpty) return null;

    // ---- Body type resolution ----
    final bodyType = _resolveBodyType(
      headers: headers,
      body: body,
      hasForm: hasForm,
      bodyFilePath: bodyFilePath,
      // --data-urlencode is an explicit pre-encoded value: keep it raw so the
      // body editor shows it verbatim instead of re-splitting into form rows.
      preferRaw: urlencodeData,
    );

    // For urlencoded bodies, surface the k=v pairs as form rows so the FORM
    // editor shows them; keep `body` empty so the serializer reads formFields.
    var resolvedBody = body;
    var resolvedFields = formFields;
    if (bodyType == BodyType.urlencoded && !hasForm) {
      resolvedFields = _formFieldsFromUrlEncoded(body);
      resolvedBody = '';
    } else if (bodyType == BodyType.binary) {
      resolvedBody = '';
    }

    return HttpRequestConfigEntity(
      id: id,
      method: method,
      url: url,
      headers: headers,
      body: resolvedBody,
      auth: auth,
      bodyType: bodyType,
      formFields: resolvedFields,
      bodyFilePath: bodyFilePath,
    );
  }

  /// Decides the [BodyType] from the available signals. JSON content (explicit
  /// header or parseable body) and any other free-form payload land as `raw` so
  /// they show in the editor; clear `k=v&k=v` pairs become `urlencoded`.
  static BodyType _resolveBodyType({
    required Map<String, String> headers,
    required String body,
    required bool hasForm,
    required String? bodyFilePath,
    required bool preferRaw,
  }) {
    if (hasForm) return BodyType.multipart;
    if (bodyFilePath != null && body.isEmpty) return BodyType.binary;
    if (body.isEmpty) return BodyType.none;

    final contentType = _headerValue(headers, 'content-type')?.toLowerCase();
    if (contentType != null) {
      if (contentType.contains('application/json')) return BodyType.raw;
      if (contentType.contains('application/x-www-form-urlencoded')) {
        return BodyType.urlencoded;
      }
    }

    if (preferRaw) return BodyType.raw;
    if (_isJson(body)) return BodyType.raw;
    if (_looksUrlEncoded(body)) return BodyType.urlencoded;
    return BodyType.raw;
  }

  /// `a=1&b=2` -> two text form rows. Values are URL-decoded best-effort.
  static List<MultipartFieldEntity> _formFieldsFromUrlEncoded(String body) {
    final fields = <MultipartFieldEntity>[];
    for (final pair in body.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final name = eq == -1 ? pair : pair.substring(0, eq);
      final value = eq == -1 ? '' : pair.substring(eq + 1);
      fields.add(
        MultipartFieldEntity(
          name: _tryDecodeComponent(name),
          value: _tryDecodeComponent(value),
        ),
      );
    }
    return fields;
  }

  /// `name=value` / `name=@file` (and `@file;type=...` style hints, ignored
  /// beyond the path) -> a multipart field row. Returns null if there's no `=`.
  static MultipartFieldEntity? _parseFormField(String spec) {
    final eq = spec.indexOf('=');
    if (eq == -1) return null;
    final name = spec.substring(0, eq);
    final rest = spec.substring(eq + 1);
    if (rest.startsWith('@') || rest.startsWith('<')) {
      var path = rest.substring(1);
      // Drop curl per-field hints like `;type=image/png` / `;filename=...`.
      final semi = path.indexOf(';');
      if (semi != -1) path = path.substring(0, semi);
      return MultipartFieldEntity(name: name, isFile: true, filePath: path);
    }
    return MultipartFieldEntity(name: name, value: rest);
  }

  /// `-u user:pass` -> a structured basic-auth map. The serializer derives the
  /// `Authorization` header at send time, so we never emit one here (matches
  /// the OpenAPI importer + the send pipeline's auth handling).
  static Map<String, String> _basicAuthFromUserArg(String userArg) {
    final colon = userArg.indexOf(':');
    final username = colon == -1 ? userArg : userArg.substring(0, colon);
    final password = colon == -1 ? '' : userArg.substring(colon + 1);
    return AuthConfig(
      type: AuthType.basic,
      username: username,
      password: password,
    ).toMap();
  }

  /// Splits a `Key: Value` header string on the first colon (trimming both).
  static void _addHeader(Map<String, String> headers, String headerStr) {
    final colonIndex = headerStr.indexOf(':');
    if (colonIndex == -1) return;
    final key = headerStr.substring(0, colonIndex).trim();
    final value = headerStr.substring(colonIndex + 1).trim();
    if (key.isEmpty) return;
    headers[key] = value;
  }

  static String _clampMethod(String method) {
    final upper = method.toUpperCase();
    if (HttpMethods.all.contains(upper)) return upper;
    // HEAD/OPTIONS aren't in HttpMethods.all but are valid curl verbs we infer;
    // keep them verbatim rather than silently rewriting to GET.
    if (upper == 'HEAD' || upper == 'OPTIONS') return upper;
    return 'GET';
  }

  static bool _isJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    if (!(trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed.startsWith('"'))) {
      return false;
    }
    try {
      jsonDecode(trimmed);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// True for bodies that look like `k=v&k=v` (no whitespace, has `=`).
  static bool _looksUrlEncoded(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty || !trimmed.contains('=')) return false;
    if (trimmed.contains('\n')) return false;
    // Each `&`-segment must look like `key=...` (key non-empty, no spaces).
    for (final seg in trimmed.split('&')) {
      if (seg.isEmpty) return false;
      final eq = seg.indexOf('=');
      if (eq <= 0) return false;
      if (seg.contains(' ')) return false;
    }
    return true;
  }

  static String _tryDecodeComponent(String s) {
    // Uri.decodeComponent throws ArgumentError (an Error subtype) on malformed
    // percent-escapes. Pre-validate instead of catching the Error: every `%`
    // must be followed by two hex digits, else return the verbatim segment.
    if (!_hasWellFormedPercentEscapes(s)) return s;
    return Uri.decodeComponent(s);
  }

  static bool _hasWellFormedPercentEscapes(String s) {
    for (var i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) != 0x25) continue; // '%'
      if (i + 2 >= s.length) return false;
      if (!_isHexDigit(s.codeUnitAt(i + 1)) ||
          !_isHexDigit(s.codeUnitAt(i + 2))) {
        return false;
      }
    }
    return true;
  }

  static bool _isHexDigit(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x46) || // A-F
      (c >= 0x61 && c <= 0x66); // a-f

  /// `name=value` -> `name=<encoded value>`; bare token -> fully encoded;
  /// a leading `=` (`=value`) -> encoded value only, the `=` is dropped (curl
  /// docs: "the preceding = symbol is not included in the data").
  static String _urlEncodeData(String data) {
    final eq = data.indexOf('=');
    if (eq == -1) return Uri.encodeComponent(data);
    if (eq == 0) return Uri.encodeComponent(data.substring(1));
    final name = data.substring(0, eq);
    final value = Uri.encodeComponent(data.substring(eq + 1));
    return '$name=$value';
  }

  static bool _hasHeader(Map<String, String> h, String name) =>
      _headerValue(h, name) != null;

  static String? _headerValue(Map<String, String> h, String name) {
    final l = name.toLowerCase();
    for (final entry in h.entries) {
      if (entry.key.toLowerCase() == l) return entry.value;
    }
    return null;
  }

  static bool _looksLikeUrl(String s) =>
      s.startsWith('http://') ||
      s.startsWith('https://') ||
      s.startsWith('localhost') ||
      _domainish.hasMatch(s) ||
      _hostPort.hasMatch(s);

  /// Shell-style tokenizer. Handles:
  /// - single quotes `'...'`: literal, may span newlines, no escapes inside;
  /// - ANSI-C quotes `$'...'`: `\`-escapes honored (`\'`, `\\`, `\"`, `\n`,
  ///   `\t`, `\r`, `\xHH`, `\uXXXX`); unknown escapes keep the backslash.
  ///   Emitted by Chrome/Firefox's "Copy as cURL" whenever the body contains
  ///   an apostrophe (e.g. `--data-raw $'{"name":"O\'Brien"}'`);
  /// - double quotes `"..."`: may span newlines, with `\` escapes (`\"`, `\\`,
  ///   `\$`, `` \` ``); other escapes keep the backslash;
  /// - unquoted `\<char>` escapes that char;
  /// - a `\` immediately before a newline is a line continuation (both dropped);
  /// - whitespace (incl. newlines) separates tokens outside quotes.
  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var hasToken = false; // distinguishes `''` (empty token) from no token
    final chars = input.runes.toList();

    void flush() {
      if (hasToken) {
        tokens.add(buffer.toString());
        buffer.clear();
        hasToken = false;
      }
    }

    var i = 0;
    while (i < chars.length) {
      final c = chars[i];

      if (c == 0x24 && i + 1 < chars.length && chars[i + 1] == 0x27) {
        // ANSI-C quoting: $'...'.
        hasToken = true;
        i += 2; // skip `$'`
        while (i < chars.length && chars[i] != 0x27) {
          if (chars[i] == 0x5C && i + 1 < chars.length) {
            final next = chars[i + 1];
            if (next == 0x27 || next == 0x5C || next == 0x22) {
              // \' \\ \"  -> literal escaped char
              buffer.writeCharCode(next);
              i += 2;
            } else if (next == 0x6E) {
              buffer.writeCharCode(0x0A); // \n
              i += 2;
            } else if (next == 0x74) {
              buffer.writeCharCode(0x09); // \t
              i += 2;
            } else if (next == 0x72) {
              buffer.writeCharCode(0x0D); // \r
              i += 2;
            } else if (next == 0x78 &&
                i + 3 < chars.length &&
                _isHexDigit(chars[i + 2]) &&
                _isHexDigit(chars[i + 3])) {
              // \xHH
              final code = int.parse(
                String.fromCharCodes([chars[i + 2], chars[i + 3]]),
                radix: 16,
              );
              buffer.writeCharCode(code);
              i += 4;
            } else if (next == 0x75 &&
                i + 5 < chars.length &&
                _isHexDigit(chars[i + 2]) &&
                _isHexDigit(chars[i + 3]) &&
                _isHexDigit(chars[i + 4]) &&
                _isHexDigit(chars[i + 5])) {
              // \uXXXX
              final code = int.parse(
                String.fromCharCodes([
                  chars[i + 2],
                  chars[i + 3],
                  chars[i + 4],
                  chars[i + 5],
                ]),
                radix: 16,
              );
              buffer.writeCharCode(code);
              i += 6;
            } else {
              // Unknown escape: keep the backslash verbatim (shell behavior).
              buffer.writeCharCode(0x5C);
              i++;
            }
            continue;
          }
          buffer.writeCharCode(chars[i]);
          i++;
        }
        i++; // skip closing quote (tolerate EOF)
      } else if (c == 0x27) {
        // Single quote: copy verbatim until the closing quote.
        hasToken = true;
        i++;
        while (i < chars.length && chars[i] != 0x27) {
          buffer.writeCharCode(chars[i]);
          i++;
        }
        i++; // skip closing quote (tolerate EOF)
      } else if (c == 0x22) {
        // Double quote: honor backslash escapes.
        hasToken = true;
        i++;
        while (i < chars.length && chars[i] != 0x22) {
          if (chars[i] == 0x5C && i + 1 < chars.length) {
            final next = chars[i + 1];
            if (next == 0x22 || next == 0x5C || next == 0x24 || next == 0x60) {
              // \" \\ \$ \`  -> literal escaped char
              buffer.writeCharCode(next);
              i += 2;
              continue;
            }
            if (next == 0x0A) {
              // backslash-newline inside double quotes: line continuation
              i += 2;
              continue;
            }
            // Unknown escape: keep the backslash (shell behavior).
            buffer.writeCharCode(0x5C);
            i++;
            continue;
          }
          buffer.writeCharCode(chars[i]);
          i++;
        }
        i++; // skip closing quote (tolerate EOF)
      } else if (c == 0x5C) {
        // Backslash outside quotes.
        if (i + 1 < chars.length) {
          final next = chars[i + 1];
          if (next == 0x0A) {
            // Line continuation: drop `\` + newline.
            i += 2;
            continue;
          }
          if (next == 0x0D && i + 2 < chars.length && chars[i + 2] == 0x0A) {
            // CRLF line continuation.
            i += 3;
            continue;
          }
          if (!hasToken && (next == 0x20 || next == 0x09)) {
            // A backslash at a token boundary followed by horizontal whitespace
            // is a line continuation whose newline was collapsed to a space by
            // a single-line text field on paste — web/Windows do this, macOS
            // keeps the newline. Drop it like a real `\`+newline so the trailing
            // flags aren't swallowed. A mid-token `\ ` (hasToken) is left as a
            // genuine escaped space below.
            i += 2;
            continue;
          }
          // Escape the next char (e.g. `\ ` -> space inside a token).
          hasToken = true;
          buffer.writeCharCode(next);
          i += 2;
          continue;
        }
        i++; // trailing backslash at EOF: drop it
      } else if (_isWhitespace(c)) {
        flush();
        i++;
      } else {
        hasToken = true;
        buffer.writeCharCode(c);
        i++;
      }
    }
    flush();
    return tokens;
  }

  static bool _isWhitespace(int c) =>
      c == 0x20 || // space
      c == 0x09 || // tab
      c == 0x0A || // newline
      c == 0x0D; // carriage return

  /// Generates a curl command from an [HttpRequestConfigEntity]. Delegates to
  /// [CodeGenService] so auth and body-type are reflected (single source of
  /// truth for code generation).
  static String generate(HttpRequestConfigEntity config) =>
      CodeGenService.generate(config, CodeGenTarget.curl);
}

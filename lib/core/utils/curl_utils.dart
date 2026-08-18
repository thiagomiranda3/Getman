// Full cURL command PARSER: tokenizes a pasted `curl ...` string (handling
// shell/ANSI-C/double quoting and `\`-newline line continuations), reads its
// flags (-X/-H/-d/--data-raw/--data-urlencode/--json/-F/-u/-b/-G/-T/...), and
// resolves the method + body type into an HttpRequestConfigEntity. Powers
// the URL bar's curl-paste shortcut (see url_bar.dart's `_handleUrlChanged`).
//
// Gotchas: method/body-type are INFERRED when -X/--request isn't given
// (HEAD if -I, GET if -G, PUT if -T/--upload-file, POST if any -d/-F/--json
// data, else GET); -d/--data/--data-binary/--json honor a leading `@file`
// reference while --data-raw explicitly does not (matches curl's own
// semantics). `--next` STOPS the parse — only the first request of a chained
// command is imported. Short-flag bundles whose letters are ALL known
// (`-Is`, `-fsSL`, `-sXPOST`) are pre-expanded into individual flags before
// dispatch (`_expandShortBundle`), so modeled letters like -I/-G keep their
// meaning anywhere in the bundle; a bundle containing any unknown letter
// stays whole and counts as one unknown flag. Once an UNKNOWN dash-flag is
// seen, a bare domain-ish token is no longer trusted as the URL (it might be
// that flag's value); an explicit http(s) scheme or localhost is required
// from there on.
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
  /// discarded so it isn't mistaken for the URL — _looksLikeUrl accepts bare
  /// domain-ish tokens, so an unconsumed value steals the URL slot and the
  /// real URL (arriving second) is dropped (`curl -c cookies.txt https://…`
  /// imported with url == 'cookies.txt'; `--oauth2-bearer eyJhbG.ciOiJI.x`
  /// imported the JWT as the URL). Sorted by long-flag name, each short
  /// alias directly before its long form. Flags UNLISTED here still can't
  /// steal the slot outright: seeing any unknown dash-flag flips the parse
  /// loop into requiring an explicit scheme on the URL token.
  static const _skipValueFlags = {
    '--abstract-unix-socket',
    '--alt-svc',
    '--aws-sigv4',
    '--cacert',
    '--capath',
    '-E',
    '--cert',
    '--cert-type',
    '--ciphers',
    '-K',
    '--config',
    '--connect-timeout',
    '--connect-to',
    '-C',
    '--continue-at',
    '-c',
    '--cookie-jar',
    '--crlfile',
    '--curves',
    '--dns-interface',
    '--dns-ipv4-addr',
    '--dns-ipv6-addr',
    '--dns-servers',
    '--doh-url',
    '-D',
    '--dump-header',
    '--etag-compare',
    '--etag-save',
    '--expect100-timeout',
    '--happy-eyeballs-timeout-ms',
    '--hostpubmd5',
    '--hostpubsha256',
    '--interface',
    '--keepalive-time',
    '--key',
    '--key-type',
    '--limit-rate',
    '--local-port',
    '--login-options',
    '--mail-auth',
    '--mail-from',
    '--mail-rcpt',
    '--max-filesize',
    '--max-redirs',
    '-m',
    '--max-time',
    '--netrc-file',
    '--noproxy',
    // The bearer token is itself domain-ish (`a.b.c` JWT shape), so before
    // this entry it won the URL slot over the real URL.
    '--oauth2-bearer',
    '-o',
    '--output',
    '--output-dir',
    '--pass',
    '--pinnedpubkey',
    '--proto',
    '--proto-default',
    '--proto-redir',
    '-x',
    '--proxy',
    '--proxy-cacert',
    '--proxy-capath',
    '--proxy-cert',
    '--proxy-cert-type',
    '--proxy-ciphers',
    '--proxy-crlfile',
    '--proxy-header',
    '--proxy-key',
    '--proxy-key-type',
    '--proxy-pass',
    '--proxy-pinnedpubkey',
    '--proxy-service-name',
    '--proxy-tls13-ciphers',
    '--proxy-tlsauthtype',
    '--proxy-tlspassword',
    '--proxy-tlsuser',
    '-U',
    '--proxy-user',
    '--proxy1.0',
    '-r',
    '--range',
    '--request-target',
    '--resolve',
    '--retry',
    '--retry-delay',
    '--retry-max-time',
    '--socks4',
    '--socks4a',
    '--socks5',
    '--socks5-hostname',
    '-Y',
    '--speed-limit',
    '-y',
    '--speed-time',
    '--stderr',
    '-t',
    '--telnet-option',
    '--tftp-blksize',
    '-z',
    '--time-cond',
    '--tls-max',
    '--tls13-ciphers',
    '--tlsauthtype',
    '--tlspassword',
    '--tlsuser',
    '--trace',
    '--trace-ascii',
    '--unix-socket',
    // -T/--upload-file are shadowed by their modeled branch in the parse
    // loop; kept here so a future reorder can't regress URL detection.
    '-T',
    '--upload-file',
    '--url-query',
    '--variable',
    '-w',
    '--write-out',
  };

  /// No-value flags we recognize and deliberately ignore. Being listed here
  /// keeps them from tripping the unknown-flag URL guard in the parse loop
  /// (an unknown flag might be value-taking, so after one appears a bare
  /// domain token can no longer be trusted as the URL). curl's `--no-<opt>`
  /// negation forms are matched by prefix at the call site, not listed.
  static const _ignoredBooleanFlags = {
    '-#',
    '--progress-bar',
    '-0',
    '--http1.0',
    '--http1.1',
    '--http2',
    '--http2-prior-knowledge',
    '--http3',
    '--http3-only',
    '-1',
    '--tlsv1',
    '--tlsv1.0',
    '--tlsv1.1',
    '--tlsv1.2',
    '--tlsv1.3',
    '-2',
    '--sslv2',
    '-3',
    '--sslv3',
    '-4',
    '--ipv4',
    '-6',
    '--ipv6',
    '--anyauth',
    '--basic',
    '--digest',
    '--negotiate',
    '--ntlm',
    '--ntlm-wb',
    '--compressed',
    '--tr-encoding',
    '--create-dirs',
    '--crlf',
    '-q',
    '--disable',
    '--disallow-username-in-url',
    '--doh-cert-status',
    '--doh-insecure',
    '-f',
    '--fail',
    '--fail-early',
    '--fail-with-body',
    '--false-start',
    '-g',
    '--globoff',
    '--haproxy-protocol',
    '-i',
    '--include',
    '-k',
    '--insecure',
    '-j',
    '--junk-session-cookies',
    '-L',
    '--location',
    '--location-trusted',
    '-n',
    '--netrc',
    '--netrc-optional',
    '-N',
    '--no-buffer',
    '-Z',
    '--parallel',
    '--parallel-immediate',
    '--path-as-is',
    '--post301',
    '--post302',
    '--post303',
    '-J',
    '--remote-header-name',
    '-O',
    '--remote-name',
    '--remote-name-all',
    '-R',
    '--remote-time',
    '--retry-all-errors',
    '--retry-connrefused',
    '-s',
    '--silent',
    '-S',
    '--show-error',
    '--ssl',
    '--ssl-no-revoke',
    '--ssl-reqd',
    '--ssl-revoke-best-effort',
    '--styled-output',
    '--tcp-fastopen',
    '--tcp-nodelay',
    '--trace-time',
    '-v',
    '--verbose',
    '--xattr',
  };

  /// Splits an argument into (flag, inlineValue): a long flag's `=value`
  /// (`--header=X: y`) or a short flag's glued value (`-XPOST` ->
  /// (`-X`, `POST`)). Fully-known short bundles never arrive here —
  /// [_expandShortBundle] breaks them apart before dispatch — so a
  /// multi-letter short token whose first letter is NOT value-taking is a
  /// bundle with an unknown letter and passes through whole, landing in the
  /// parse loop's unknown-flag arm. Plain tokens pass through with a null
  /// inline value.
  static (String, String?) _splitFlag(String raw) {
    if (raw.startsWith('--') && raw.contains('=')) {
      final eq = raw.indexOf('=');
      return (raw.substring(0, eq), raw.substring(eq + 1));
    }
    if (raw.length > 2 &&
        raw.startsWith('-') &&
        !raw.startsWith('--') &&
        _gluedShortFlags.contains(raw[1])) {
      return ('-${raw[1]}', raw.substring(2));
    }
    return (raw, null);
  }

  /// Pre-expands a fully-known short-flag bundle into individual flags
  /// processed in order. Every letter must be a known single-letter flag:
  /// ignored booleans ([_bundleBooleanLetters]), modeled booleans
  /// ([_modeledBooleanLetters]) and at most one TRAILING value-taking letter
  /// from [_gluedShortFlags], which keeps its glued remainder (`-sXPOST` ->
  /// `-s` + `-XPOST`) or, bare (`-sX POST`, `-sH 'K: v'`), takes the next
  /// token via the caller — exactly like an unbundled short flag. So `-Is`
  /// -> `-I -s` (HEAD), `-Gd` -> `-G -d` (query fold), `-fsSL` -> four
  /// ignored booleans. Anything else — long flags, plain tokens, and
  /// notably a bundle containing an UNKNOWN letter — comes back as a single
  /// element, unchanged: the whole token then reads as one unknown flag in
  /// the parse loop (engaging the URL scheme guard) rather than silently
  /// applying a partial prefix.
  static List<String> _expandShortBundle(String raw) {
    if (raw.length <= 2 || !raw.startsWith('-') || raw.startsWith('--')) {
      return [raw];
    }
    final flags = <String>[];
    for (var i = 1; i < raw.length; i++) {
      final letter = raw[i];
      if (_bundleBooleanLetters.contains(letter) ||
          _modeledBooleanLetters.contains(letter)) {
        flags.add('-$letter');
        continue;
      }
      if (_gluedShortFlags.contains(letter)) {
        // Value-taking letter: ends the bundle, keeping any glued remainder.
        flags.add('-${raw.substring(i)}');
        return flags;
      }
      return [raw]; // unknown letter: surface the whole token untouched
    }
    return flags;
  }

  /// Single-letter value-taking flags that curl accepts with a glued argument
  /// (`-XPOST`). Letters of modeled flags plus the short skip-flag letters
  /// (`o`/`x`/`m`/... ) so `-omyfile` doesn't leak its value into URL
  /// detection.
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
    'c',
    'C',
    'D',
    'E',
    'K',
    'r',
    't',
    'U',
    'y',
    'Y',
    'z',
  };

  /// Boolean short-flag letters that may appear in a short bundle
  /// (`-sX POST`, `-fsSL`): the single-letter spellings of
  /// [_ignoredBooleanFlags]. [_expandShortBundle] expands each into its own
  /// `-x` token, which the parse loop then ignores. Modeled boolean letters
  /// (`I`/`G`) live in [_modeledBooleanLetters] instead so their semantics
  /// are applied, never ignored.
  static const _bundleBooleanLetters = {
    '#',
    '0',
    '1',
    '2',
    '3',
    '4',
    '6',
    'f',
    'g',
    'i',
    'j',
    'J',
    'k',
    'L',
    'n',
    'N',
    'O',
    'q',
    'R',
    's',
    'S',
    'v',
    'Z',
  };

  /// Modeled boolean short-flag letters — `-I` (--head -> HEAD inference)
  /// and `-G` (--get -> query fold). Kept apart from
  /// [_bundleBooleanLetters] because these letters carry semantics: they may
  /// sit ANYWHERE in a bundle (`-Is`, `-IL`, `-Gd`) and [_expandShortBundle]
  /// surfaces each as its own token so the modeled branch in
  /// `_CurlParseState.applyMethodOrUrlFlag` still fires. (The old
  /// trailing-letter-only bundle scan turned `-Is example.com` into one
  /// unknown flag, tripping the URL scheme guard and killing the import.)
  /// Add any future modeled boolean short flag here too.
  static const _modeledBooleanLetters = {'G', 'I'};

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

    final state = _CurlParseState();

    outer:
    for (var i = 1; i < args.length; i++) {
      // Fully-known short bundles (`-Is`, `-Gd`, `-fsSL`, `-sXPOST`) expand
      // into individual flags processed in order, so modeled letters (I/G)
      // keep their meaning anywhere in the bundle; any other token comes
      // back as a single element, unchanged.
      for (final raw in _expandShortBundle(args[i])) {
        // Split a long flag's inline value (`--header=X: y` ->
        // (`--header`, `X: y`)) or a short flag's glued value (`-XPOST`).
        final (flag, inlineValue) = _splitFlag(raw);

        // Reads the value for a value-taking flag: the inline/glued value if
        // present, else the next token. Returns null if neither exists.
        // Bundle expansion guarantees only the LAST flag of a bundle can be
        // value-taking, so consuming args[i + 1] here never skips an
        // expanded flag.
        String? takeValue() {
          if (inlineValue != null) return inlineValue;
          if (i + 1 < args.length) return args[++i];
          return null;
        }

        if (flag == '--next' || flag == '-:') {
          // `--next` starts a SECOND independent request on the same command
          // line; merging its flags into the first corrupts both. Import the
          // first request only.
          break outer;
        }
        // The three modeled flag families are disjoint sets, so dispatch
        // order between them cannot change behavior — each token matches at
        // most one. They MUST run before the _skipValueFlags check:
        // -T/--upload-file are listed there too and would otherwise lose
        // their modeled semantics.
        if (state.applyMethodOrUrlFlag(flag, takeValue) ||
            state.applyDataFlag(flag, takeValue) ||
            state.applyHeaderOrAuthFlag(flag, takeValue)) {
          continue;
        }
        if (_skipValueFlags.contains(flag)) {
          takeValue(); // consume + discard the unmodeled value
        } else if (_ignoredBooleanFlags.contains(flag) ||
            flag.startsWith('--no-')) {
          // Recognized no-value flag (or curl's `--no-<option>` negation
          // form): ignore it WITHOUT engaging the unknown-flag URL guard
          // below.
        } else if (flag.startsWith('-')) {
          // Unknown flag. If it carried an inline `=value`, it's fully
          // consumed. Otherwise treat it as a boolean flag and ignore it
          // (don't swallow the next token — it might be the URL). But it
          // might really be value-taking, so stop trusting bare domain-ish
          // tokens as the URL.
          state.sawUnknownFlag = true;
        } else if (state.url.isEmpty &&
            _looksLikeUrl(raw, requireScheme: state.sawUnknownFlag)) {
          state.url = raw;
        }
      }
    }

    // ---- Method inference (when -X/--request was not given) ----
    var method = state.method;
    if (!state.explicitMethod) {
      if (state.headRequest) {
        method = 'HEAD';
      } else if (state.forceGet) {
        method = 'GET';
      } else if (state.uploadFile) {
        method = 'PUT';
      } else if (state.hasData || state.hasForm) {
        method = 'POST';
      } else {
        method = 'GET';
      }
    }
    method ??= 'GET';
    method = _clampMethod(method);

    // ---- Body assembly ----
    // curl concatenates plain -d/--data values with '&'.
    var body = state.dataParts.join('&');
    var url = state.url;

    // -G turns accumulated data into the query string.
    if (state.forceGet && body.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url$sep$body';
      body = '';
      state.dataParts.clear();
      state.hasData = false;
    }

    if (url.isEmpty) return null;

    // ---- Body type resolution ----
    final bodyType = _resolveBodyType(
      headers: state.headers,
      body: body,
      hasForm: state.hasForm,
      bodyFilePath: state.bodyFilePath,
      // --data-urlencode is an explicit pre-encoded value: keep it raw so the
      // body editor shows it verbatim instead of re-splitting into form rows.
      preferRaw: state.urlencodeData,
    );

    // For urlencoded bodies, surface the k=v pairs as form rows so the FORM
    // editor shows them; keep `body` empty so the serializer reads formFields.
    var resolvedBody = body;
    var resolvedFields = state.formFields;
    if (bodyType == BodyType.urlencoded && !state.hasForm) {
      resolvedFields = _formFieldsFromUrlEncoded(body);
      resolvedBody = '';
    } else if (bodyType == BodyType.binary) {
      resolvedBody = '';
    }

    return HttpRequestConfigEntity(
      id: id,
      method: method,
      url: url,
      headers: state.headers,
      body: resolvedBody,
      auth: state.auth,
      bodyType: bodyType,
      formFields: resolvedFields,
      bodyFilePath: state.bodyFilePath,
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
    if (_extendedMethods.contains(upper)) return upper;
    return 'GET';
  }

  /// Verbs beyond HttpMethods.all that [_clampMethod] keeps verbatim:
  /// HEAD/OPTIONS (curl verbs we infer ourselves) plus the common extended
  /// family (cache purge + WebDAV + report/search/query) — parity with the
  /// Postman importer, which stores arbitrary methods verbatim. Anything
  /// else (typos, corrupt tokens) still clamps to GET: the entity stores a
  /// free string, but the URL bar's method dropdown
  /// (request_kind_method_selector.dart) only lists HttpMethods.all and
  /// asserts on values outside its items, so arbitrary strings stay fenced
  /// to this deliberate, Postman-parity set.
  static const _extendedMethods = {
    'HEAD',
    'OPTIONS',
    'PURGE',
    'PROPFIND',
    'MKCOL',
    'COPY',
    'MOVE',
    'LOCK',
    'UNLOCK',
    'REPORT',
    'SEARCH',
    'QUERY',
  };

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

  /// True for tokens that plausibly are the request URL. With
  /// [requireScheme] (set once an unknown dash-flag has been seen — see the
  /// parse loop) only an explicit http(s) scheme or a localhost prefix
  /// qualifies, because a bare domain-ish token might be the unknown flag's
  /// value rather than the URL.
  static bool _looksLikeUrl(String s, {bool requireScheme = false}) {
    if (s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('localhost')) {
      return true;
    }
    if (requireScheme) return false;
    return _domainish.hasMatch(s) || _hostPort.hasMatch(s);
  }

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

/// Mutable accumulator for one [CurlUtils.parse] run. The parse loop feeds
/// every recognized flag through the `apply*Flag` dispatch methods below
/// (one per flag family, split out of the former single if/else-if chain so
/// each stays under the cyclomatic-complexity gate); `parse()` then reads the
/// fields for method inference and final body assembly. Behavior-identical to
/// the inline chain: the families are disjoint flag sets, so per-token
/// dispatch order between them cannot matter.
class _CurlParseState {
  bool explicitMethod = false;
  String? method;
  String url = '';
  final Map<String, String> headers = {};
  final List<String> dataParts = [];
  bool hasData = false; // any -d/--data* flag seen (drives POST inference)

  /// True if any data came via --data-urlencode: the user already chose the
  /// encoding, so keep it a raw body rather than re-splitting into form rows.
  bool urlencodeData = false;
  bool forceGet = false;
  bool headRequest = false;
  bool uploadFile = false; // -T/--upload-file (PUT inference)

  final List<MultipartFieldEntity> formFields = [];
  bool hasForm = false;

  String? bodyFilePath; // set by `--data-binary @file`
  Map<String, String> auth = const {};

  /// Once an UNKNOWN dash-flag is seen, it might have been value-taking and
  /// its value can look domain-ish (`--oauth2-bearer eyJ…` — the JWT would
  /// steal the URL slot). From then on only a token with an explicit scheme
  /// (or localhost) is trusted as the URL.
  bool sawUnknownFlag = false;

  void _addData(String data, {bool allowFileRef = false}) {
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

  /// Method-, upload- and URL-selection flags: -X/--request, -G/--get,
  /// -I/--head, -T/--upload-file and --url. Returns true when [flag] was one
  /// of them (handled — [takeValue] consumed the value where one is taken).
  bool applyMethodOrUrlFlag(String flag, String? Function() takeValue) {
    if (flag == '-X' || flag == '--request') {
      final v = takeValue();
      if (v != null) {
        method = v.toUpperCase();
        explicitMethod = true;
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
    } else {
      return false;
    }
    return true;
  }

  /// Body-data flags: the -d/--data* family, --json and -F/--form. Returns
  /// true when [flag] was one of them (handled).
  bool applyDataFlag(String flag, String? Function() takeValue) {
    if (flag == '-d' ||
        flag == '--data' ||
        flag == '--data-ascii' ||
        flag == '--data-binary') {
      // A leading `@` is a file reference curl reads from disk. Only
      // --data-raw (below) disables that interpretation.
      final v = takeValue();
      if (v != null) _addData(v, allowFileRef: true);
    } else if (flag == '--data-raw') {
      // curl disables `@`-file interpretation for --data-raw: the value
      // always posts as literal data.
      final v = takeValue();
      if (v != null) _addData(v);
    } else if (flag == '--data-urlencode') {
      final v = takeValue();
      if (v != null) {
        urlencodeData = true;
        _addData(CurlUtils._urlEncodeData(v));
      }
    } else if (flag == '--json') {
      // curl >= 7.82: `--json <data>` is shorthand for `--data <data>` +
      // `Content-Type: application/json` + `Accept: application/json`.
      // Both headers yield to an explicit -H on either side of --json
      // (a later -H overwrites; an earlier one wins via the guard here).
      // Shares -d's `@file` semantics and POST inference.
      final v = takeValue();
      if (v != null) {
        _addData(v, allowFileRef: true);
        if (!CurlUtils._hasHeader(headers, 'content-type')) {
          headers['Content-Type'] = 'application/json';
        }
        if (!CurlUtils._hasHeader(headers, 'accept')) {
          headers['Accept'] = 'application/json';
        }
      }
    } else if (flag == '-F' || flag == '--form') {
      final v = takeValue();
      if (v != null) {
        hasForm = true;
        final field = CurlUtils._parseFormField(v);
        if (field != null) formFields.add(field);
      }
    } else {
      return false;
    }
    return true;
  }

  /// Header- and auth-shaped flags: -H/--header, -u/--user, -A/--user-agent,
  /// -e/--referer and -b/--cookie. Returns true when [flag] was one of them
  /// (handled).
  bool applyHeaderOrAuthFlag(String flag, String? Function() takeValue) {
    if (flag == '-H' || flag == '--header') {
      final v = takeValue();
      if (v != null) CurlUtils._addHeader(headers, v);
    } else if (flag == '-u' || flag == '--user') {
      final v = takeValue();
      if (v != null) auth = CurlUtils._basicAuthFromUserArg(v);
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
      if (v != null &&
          v.contains('=') &&
          !CurlUtils._hasHeader(headers, 'cookie')) {
        headers['Cookie'] = v;
      }
    } else {
      return false;
    }
    return true;
  }
}

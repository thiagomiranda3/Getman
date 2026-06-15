import 'dart:convert';

import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/code_gen_service.dart';

class CurlUtils {
  /// Common value-taking flags we don't model. Their argument is consumed and
  /// discarded so it isn't mistaken for the URL (e.g. `-e <referer> <url>`).
  static const _skipValueFlags = {
    '-A',
    '--user-agent',
    '-e',
    '--referer',
    '-o',
    '--output',
    '-F',
    '--form',
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
  };

  static final RegExp _domainish = RegExp(r'^[\w.-]+\.[\w.-]+');
  static final RegExp _hostPort = RegExp(r'^[\w.-]+:\d+');

  /// Parses a curl command into an [HttpRequestConfigEntity].
  static HttpRequestConfigEntity? parse(String curl, {required String id}) {
    // Tokenize first; the first token tells us whether this really is a curl
    // invocation. (The previous double-check — startsWith + args[0] — was
    // redundant; tokenization already handles leading whitespace.)
    final args = _splitArguments(curl.trim());
    if (args.isEmpty || args[0].toLowerCase() != 'curl') {
      return null;
    }

    var method = 'GET';
    var explicitMethod = false;
    var url = '';
    final headers = <String, String>{};
    var body = '';
    var forceGet = false;

    void addData(String data) {
      // curl concatenates multiple -d flags with '&'.
      body = body.isEmpty ? data : '$body&$data';
      if (method == 'GET' && !explicitMethod) method = 'POST';
    }

    for (var i = 1; i < args.length; i++) {
      final arg = args[i];

      if (arg == '-X' || arg == '--request') {
        if (i + 1 < args.length) {
          method = args[++i].toUpperCase();
          explicitMethod = true;
        }
      } else if (arg == '-H' || arg == '--header') {
        if (i + 1 < args.length) {
          final headerStr = args[++i];
          final colonIndex = headerStr.indexOf(':');
          if (colonIndex != -1) {
            final key = headerStr.substring(0, colonIndex).trim();
            final value = headerStr.substring(colonIndex + 1).trim();
            headers[key] = value;
          }
        }
      } else if (arg == '-d' ||
          arg == '--data' ||
          arg == '--data-raw' ||
          arg == '--data-binary' ||
          arg == '--data-ascii') {
        if (i + 1 < args.length) addData(args[++i]);
      } else if (arg == '--data-urlencode') {
        if (i + 1 < args.length) addData(_urlEncodeData(args[++i]));
      } else if (arg == '-u' || arg == '--user') {
        if (i + 1 < args.length && !_hasHeader(headers, 'authorization')) {
          headers['Authorization'] =
              'Basic ${base64.encode(utf8.encode(args[++i]))}';
        }
      } else if (arg == '-b' || arg == '--cookie') {
        if (i + 1 < args.length && !_hasHeader(headers, 'cookie')) {
          headers['Cookie'] = args[++i];
        }
      } else if (arg == '-G' || arg == '--get') {
        forceGet = true;
      } else if (arg == '--url') {
        if (i + 1 < args.length) url = args[++i];
      } else if (_skipValueFlags.contains(arg)) {
        if (i + 1 < args.length) i++; // consume + discard the unmodeled value
      } else if (!arg.startsWith('-') && url.isEmpty && _looksLikeUrl(arg)) {
        url = arg;
      }
      // Unknown boolean flags (e.g. --compressed, -s, -L) are ignored.
    }

    // -G turns accumulated data into the query string and forces GET.
    if (forceGet && body.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url$sep$body';
      body = '';
      method = 'GET';
    }

    if (url.isEmpty) return null;

    return HttpRequestConfigEntity(
      id: id,
      method: method,
      url: url,
      headers: headers,
      body: body,
    );
  }

  /// `name=value` -> `name=<encoded value>`; bare token -> fully encoded.
  static String _urlEncodeData(String data) {
    final eq = data.indexOf('=');
    if (eq == -1) return Uri.encodeComponent(data);
    final name = data.substring(0, eq);
    final value = Uri.encodeComponent(data.substring(eq + 1));
    return '$name=$value';
  }

  static bool _hasHeader(Map<String, String> h, String name) {
    final l = name.toLowerCase();
    return h.keys.any((k) => k.toLowerCase() == l);
  }

  static bool _looksLikeUrl(String s) =>
      s.startsWith('http://') ||
      s.startsWith('https://') ||
      s.startsWith('localhost') ||
      _domainish.hasMatch(s) ||
      _hostPort.hasMatch(s);

  static List<String> _splitArguments(String command) {
    final args = <String>[];
    // This regex matches:
    // 1. Single quoted strings: '...'
    // 2. Double quoted strings: "..."
    // 3. Unquoted words: [^\s]+
    final regex = RegExp(
      "'([^']*)'|"
      '"'
      '([^"]*)'
      '"'
      r'|([^\s]+)',
    );

    final matches = regex.allMatches(command);
    for (final match in matches) {
      if (match.group(1) != null) {
        args.add(match.group(1)!);
      } else if (match.group(2) != null) {
        args.add(match.group(2)!);
      } else if (match.group(3) != null) {
        args.add(match.group(3)!);
      }
    }
    return args;
  }

  /// Generates a curl command from an [HttpRequestConfigEntity]. Delegates to
  /// [CodeGenService] so auth and body-type are reflected (single source of
  /// truth for code generation).
  static String generate(HttpRequestConfigEntity config) =>
      CodeGenService.generate(config, CodeGenTarget.curl);
}

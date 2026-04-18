import 'package:getman/features/history/domain/entities/request_config_entity.dart';

class CurlUtils {
  /// Parses a curl command into an [HttpRequestConfigEntity]
  static HttpRequestConfigEntity? parse(String curl, {required String id}) {
    final trimmedCurl = curl.trim();
    if (!trimmedCurl.toLowerCase().startsWith('curl ')) {
      return null;
    }

    // Split the curl command into arguments, respecting quotes
    final args = _splitArguments(trimmedCurl);
    if (args.isEmpty || args[0].toLowerCase() != 'curl') {
      return null;
    }

    String method = 'GET';
    String url = '';
    Map<String, String> headers = {};
    String body = '';

    for (int i = 1; i < args.length; i++) {
      final arg = args[i];
      
      if (arg == '-X' || arg == '--request') {
        if (i + 1 < args.length) {
          method = args[++i].toUpperCase();
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
      } else if (arg == '-d' || arg == '--data' || arg == '--data-raw' || arg == '--data-binary') {
        if (i + 1 < args.length) {
          body = args[++i];
          if (method == 'GET') method = 'POST';
        }
      } else if (arg == '--url') {
        if (i + 1 < args.length) {
          url = args[++i];
        }
      } else if (arg.startsWith('http')) {
        url = arg;
      }
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

  static List<String> _splitArguments(String command) {
    final args = <String>[];
    // This regex matches:
    // 1. Single quoted strings: '...'
    // 2. Double quoted strings: "..."
    // 3. Unquoted words: [^\s]+
    final regex = RegExp(r"'([^']*)'|""([^""]*)""|([^\s]+)");
    
    // Let's use a more reliable regex for double quotes
    final betterRegex = RegExp(r"'([^']*)'|" + '"([^"]*)"' + r"|([^\s]+)");
    
    final matches = betterRegex.allMatches(command);
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

  /// Generates a curl command from an [HttpRequestConfigEntity]
  static String generate(HttpRequestConfigEntity config) {
    final buffer = StringBuffer();
    buffer.write('curl --request ${config.method} \\\n');
    buffer.write('  --url \'${config.url}\' \\\n');

    config.headers.forEach((key, value) {
      buffer.write('  --header \'$key: $value\' \\\n');
    });

    if (config.body.isNotEmpty) {
      // Escape single quotes in body for the curl command
      final escapedBody = config.body.replaceAll('\'', "'\\''");
      buffer.write('  --data \'$escapedBody\'');
    }

    String result = buffer.toString().trim();
    if (result.endsWith('\\')) {
      result = result.substring(0, result.length - 1).trim();
    }
    return result;
  }
}

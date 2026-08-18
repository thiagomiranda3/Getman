// Parses a URL into base/query-params/fragment and rebuilds it
// (UrlParts/parse/build/replaceQuery), keeping the URL bar and the PARAMS
// tab's row editor in sync. Encoding/decoding both skip over `{{...}}`
// variable tokens (mirroring EnvironmentResolver's grammar, plus a leading
// `$` for dynamic vars) so percent-encoding never mangles a variable
// placeholder while a params row is edited.

import 'package:getman/core/domain/entities/query_param_entity.dart';

class UrlParts {
  const UrlParts({
    required this.base,
    required this.params,
    required this.fragment,
  });
  final String base;
  final List<QueryParamEntity> params;
  final String? fragment;
}

class UrlQueryUtils {
  UrlQueryUtils._();

  // Mirrors EnvironmentResolver's grammar EXACTLY (`[^{}]+?` — names with
  // spaces/`@`/`:`/unicode and the `$` dynamics are all contractually valid).
  // A narrower character class here percent-mangled any wider token on every
  // params edit ({{api key}} → %7B%7Bapi%20key%7D%7D), after which send-time
  // resolution no longer matched it.
  static final RegExp _varToken = RegExp(r'\{\{[^{}]+?\}\}');

  static UrlParts parse(String url) {
    final hashIndex = url.indexOf('#');
    var qIndex = url.indexOf('?');
    // A '?' after the '#' is fragment text, not a query delimiter.
    if (hashIndex != -1 && qIndex > hashIndex) qIndex = -1;
    if (qIndex == -1) {
      if (hashIndex == -1) {
        return UrlParts(base: url, params: const [], fragment: null);
      }
      return UrlParts(
        base: url.substring(0, hashIndex),
        params: const [],
        fragment: url.substring(hashIndex + 1),
      );
    }

    final base = url.substring(0, qIndex);
    final afterQ = url.substring(qIndex + 1);
    final hIndex = afterQ.indexOf('#');
    final queryStr = hIndex == -1 ? afterQ : afterQ.substring(0, hIndex);
    final fragment = hIndex == -1 ? null : afterQ.substring(hIndex + 1);

    final params = <QueryParamEntity>[];
    if (queryStr.isNotEmpty) {
      for (final pair in queryStr.split('&')) {
        if (pair.isEmpty) continue;
        final eqIndex = pair.indexOf('=');
        final rawKey = eqIndex == -1 ? pair : pair.substring(0, eqIndex);
        final rawVal = eqIndex == -1 ? '' : pair.substring(eqIndex + 1);
        final key = _decode(rawKey);
        if (key.isEmpty) continue;
        params.add(QueryParamEntity(key: key, value: _decode(rawVal)));
      }
    }

    return UrlParts(base: base, params: params, fragment: fragment);
  }

  static List<QueryParamEntity> parseQuery(String url) => parse(url).params;

  static String replaceQuery(String url, List<QueryParamEntity> params) {
    final parts = parse(url);
    return build(base: parts.base, params: params, fragment: parts.fragment);
  }

  static String build({
    required String base,
    List<QueryParamEntity> params = const [],
    String? fragment,
  }) {
    final buf = StringBuffer(base);
    final rendered = <String>[];
    for (final p in params) {
      if (p.key.isEmpty) continue;
      rendered.add('${encodeComponent(p.key)}=${encodeComponent(p.value)}');
    }
    if (rendered.isNotEmpty) {
      buf
        ..write('?')
        ..write(rendered.join('&'));
    }
    if (fragment != null) {
      buf
        ..write('#')
        ..write(fragment);
    }
    return buf.toString();
  }

  /// Percent-encodes [input] while passing `{{var}}` tokens through verbatim
  /// (the same grammar the rest of this class uses). Public because the
  /// Postman mapper needs it to emit parked params in `url.query`'s
  /// still-percent-encoded convention.
  static String encodeComponent(String input) {
    if (input.isEmpty) return '';
    final buf = StringBuffer();
    var i = 0;
    for (final m in _varToken.allMatches(input)) {
      if (m.start > i) {
        buf.write(Uri.encodeComponent(input.substring(i, m.start)));
      }
      buf.write(m.group(0));
      i = m.end;
    }
    if (i < input.length) {
      buf.write(Uri.encodeComponent(input.substring(i)));
    }
    return buf.toString();
  }

  static String _decode(String input) {
    if (input.isEmpty) return '';
    final buf = StringBuffer();
    var i = 0;
    for (final m in _varToken.allMatches(input)) {
      if (m.start > i) {
        buf.write(_safeDecode(input.substring(i, m.start)));
      }
      buf.write(m.group(0));
      i = m.end;
    }
    if (i < input.length) {
      buf.write(_safeDecode(input.substring(i)));
    }
    return buf.toString();
  }

  static String _safeDecode(String input) {
    try {
      // decodeQueryComponent, not decodeComponent: in a query string `+`
      // means SPACE (the form-encoding convention every browser/curl/server
      // follows). decodeComponent left `+` literal, and the re-encode then
      // shipped `%2B` — silently turning "hello world" into "hello+world"
      // on the wire the moment any params row was edited.
      return Uri.decodeQueryComponent(input);
    } on Object catch (_) {
      return input;
    }
  }
}

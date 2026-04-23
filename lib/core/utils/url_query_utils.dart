import '../domain/entities/query_param_entity.dart';

class UrlParts {
  final String base;
  final List<QueryParamEntity> params;
  final String? fragment;

  const UrlParts({
    required this.base,
    required this.params,
    required this.fragment,
  });
}

class UrlQueryUtils {
  UrlQueryUtils._();

  static final RegExp _varToken = RegExp(r'\{\{[A-Za-z0-9_\-\.\s]+\}\}');

  static UrlParts parse(String url) {
    final qIndex = url.indexOf('?');
    if (qIndex == -1) {
      final hIndex = url.indexOf('#');
      if (hIndex == -1) {
        return UrlParts(base: url, params: const [], fragment: null);
      }
      return UrlParts(
        base: url.substring(0, hIndex),
        params: const [],
        fragment: url.substring(hIndex + 1),
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
      rendered.add('${_encode(p.key)}=${_encode(p.value)}');
    }
    if (rendered.isNotEmpty) {
      buf.write('?');
      buf.write(rendered.join('&'));
    }
    if (fragment != null) {
      buf.write('#');
      buf.write(fragment);
    }
    return buf.toString();
  }

  static String _encode(String input) {
    if (input.isEmpty) return '';
    final buf = StringBuffer();
    int i = 0;
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
    int i = 0;
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
      return Uri.decodeComponent(input);
    } catch (_) {
      return input;
    }
  }
}

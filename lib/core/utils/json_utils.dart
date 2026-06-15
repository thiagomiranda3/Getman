import 'dart:convert';
import 'package:flutter/foundation.dart';

class JsonUtils {
  static Future<String> prettify(String? body) async {
    if (body == null || body.isEmpty) return '';
    // Short-circuit: HTML, plain-text, and binary responses never contain
    // top-level JSON objects/arrays, so skip isolate spawn entirely.
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return body;
    return compute(_prettifyJson, body);
  }

  static String _prettifyJson(String body) {
    try {
      final decoded = json.decode(body);
      return const JsonEncoder.withIndent('    ').convert(decoded);
    } on Object catch (_) {
      // Not valid JSON (an XML/HTML error page, a JS array literal, the
      // over-1-MB placeholder, etc.). Returning the body verbatim is the
      // intended contract here — a parse miss on an arbitrary HTTP response is
      // normal, not a bug, so it is deliberately not logged.
      return body;
    }
  }
}

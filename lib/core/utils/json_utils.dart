import 'dart:convert';
import 'package:flutter/foundation.dart';

class JsonUtils {
  static Future<String> prettify(String? body) async {
    if (body == null || body.isEmpty) return '';
    return compute(_prettifyJson, body);
  }

  static String _prettifyJson(String body) {
    try {
      final decoded = json.decode(body);
      return const JsonEncoder.withIndent('    ').convert(decoded);
    } catch (e) {
      debugPrint('JsonUtils.prettify: not valid JSON, returning raw body ($e)');
      return body;
    }
  }
}

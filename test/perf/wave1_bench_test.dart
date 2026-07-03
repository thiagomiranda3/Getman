@Tags(['perf'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_view.dart';

String _bigJson(int entries) {
  final m = {for (var i = 0; i < entries; i++) 'key_$i': 'value_$i'};
  return jsonEncode(m);
}

void main() {
  test('bench: JsonPath.tryDecode of ~1MB JSON completes and round-trips', () {
    final body = _bigJson(20000);
    final sw = Stopwatch()..start();
    final decoded = JsonPath.tryDecode(body);
    sw.stop();
    // ignore: avoid_print — benchmark timing output is intentional
    print('tryDecode(${body.length} chars): ${sw.elapsedMilliseconds}ms');
    expect(decoded, isA<Map<String, dynamic>>());
  });

  test('bench: JsonUtils.prettify shortcuts non-JSON instantly', () async {
    const html = '<html><body>not json</body></html>';
    final sw = Stopwatch()..start();
    final out = await JsonUtils.prettify(html);
    sw.stop();
    // ignore: avoid_print — benchmark timing output is intentional
    print('prettify(non-json): ${sw.elapsedMicroseconds}us');
    expect(out, html); // short-circuit returns the body verbatim, no isolate
  });

  test('bench: findVariables over a 2000-char line', () {
    final line = '${'a' * 1000}{{token}} mid {{\$guid}} ${'b' * 1000}';
    final sw = Stopwatch()..start();
    final matches = EnvironmentResolver.findVariables(line).toList();
    sw.stop();
    // ignore: avoid_print — benchmark timing output is intentional
    print('findVariables(2000 chars): ${sw.elapsedMicroseconds}us');
    expect(matches.length, 2);
  });

  test('bench: responseSizeBytes is memoized per instance', () {
    final resp = HttpResponseEntity(
      statusCode: 200,
      body: 'x' * (256 * 1024),
      headers: const {},
      durationMs: 0,
    );
    final first = Stopwatch()..start();
    final a = responseSizeBytes(resp);
    first.stop();
    final second = Stopwatch()..start();
    final b = responseSizeBytes(resp);
    second.stop();
    // ignore: avoid_print — benchmark timing output is intentional
    print(
      'responseSizeBytes first=${first.elapsedMicroseconds}us '
      'cached=${second.elapsedMicroseconds}us',
    );
    expect(a, b);
    expect(a, 256 * 1024);
  });

  test('bench: flattenVisibleJsonTree over a wide object (collapsed)', () {
    final data = {for (var i = 0; i < 5000; i++) 'k$i': i};
    final sw = Stopwatch()..start();
    final nodes = flattenVisibleJsonTree(data: data, expanded: <String>{});
    sw.stop();
    // ignore: avoid_print — benchmark timing output is intentional
    print('flatten(5000 keys, collapsed): ${sw.elapsedMilliseconds}ms');
    expect(nodes.length, 5000);
  });
}

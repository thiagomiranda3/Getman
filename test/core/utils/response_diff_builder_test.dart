import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/core/utils/response_diff_builder.dart';

HttpResponseEntity _resp({
  int status = 200,
  String body = '',
  Map<String, String> headers = const {},
}) {
  return HttpResponseEntity(
    statusCode: status,
    body: body,
    headers: headers,
    durationMs: 1,
  );
}

void main() {
  group('ResponseDiffBuilder.build', () {
    test(
      'many changed short lines fall back without quadratic allocation',
      () async {
        // Budget is documented in tabs-and-panels.md; characters alone do not
        // bound the LCS matrix.
        final model = await ResponseDiffBuilder.build(
          _resp(body: List.generate(4000, (i) => 'a$i').join('\n')),
          _resp(body: List.generate(4000, (i) => 'b$i').join('\n')),
        );
        expect(model.tooLarge, isTrue);
        expect(model.bodyLines, isEmpty);
      },
    );

    test('minified JSON is budgeted after expansion into many lines', () async {
      final model = await ResponseDiffBuilder.build(
        _resp(body: '[${List.filled(2000, '0').join(',')}]'),
        _resp(body: '[${List.filled(2000, '1').join(',')}]'),
      );
      expect(model.tooLarge, isTrue);
    });

    test('identical many-line bodies need no diff matrix', () async {
      final body = List.filled(100000, 'a').join('\n');
      final model = await ResponseDiffBuilder.build(
        _resp(body: body),
        _resp(body: body),
      );
      expect(model.bodiesIdentical, isTrue);
      expect(model.tooLarge, isFalse);
    });

    test(
      'deep minified JSON is rejected before quadratic formatting expansion',
      () async {
        // Formatting budget is documented in tabs-and-panels.md.
        final prefix = '[' * 10000;
        final suffix = ']' * 10000;
        final model = await ResponseDiffBuilder.build(
          _resp(body: '${prefix}0$suffix'),
          _resp(body: '${prefix}1$suffix'),
        );
        expect(model.tooLarge, isTrue);
        expect(model.bodyLines, isEmpty);
      },
    );

    test('copies both status codes through', () async {
      final model = await ResponseDiffBuilder.build(
        _resp(),
        _resp(status: 404),
      );
      expect(model.leftStatus, 200);
      expect(model.rightStatus, 404);
    });

    test('identical bodies set bodiesIdentical', () async {
      final model = await ResponseDiffBuilder.build(
        _resp(body: 'hello\nworld'),
        _resp(body: 'hello\nworld'),
      );
      expect(model.bodiesIdentical, isTrue);
      expect(
        model.bodyLines.map((l) => l.kind),
        everyElement(DiffLineKind.equal),
      );
    });

    test('different bodies are diffed line-level after prettify', () async {
      final model = await ResponseDiffBuilder.build(
        _resp(body: '{"a":1}'),
        _resp(body: '{"a":2}'),
      );
      expect(model.bodiesIdentical, isFalse);
      expect(
        model.bodyLines.where((l) => l.kind == DiffLineKind.removed),
        isNotEmpty,
      );
      expect(
        model.bodyLines.where((l) => l.kind == DiffLineKind.added),
        isNotEmpty,
      );
    });

    test(
      'header added/removed/changed deltas, case-insensitive key match',
      () async {
        final model = await ResponseDiffBuilder.build(
          _resp(
            headers: const {
              'Content-Type': 'application/json',
              'X-Old': 'gone',
              'ETag': 'v1',
            },
          ),
          _resp(
            headers: const {
              'content-type': 'application/json', // same value, casing differs
              'X-New': 'fresh',
              'ETag': 'v2',
            },
          ),
        );
        final byKey = {
          for (final d in model.headerDeltas) d.key.toLowerCase(): d,
        };
        // content-type unchanged -> no delta despite casing difference.
        expect(byKey.containsKey('content-type'), isFalse);
        expect(byKey['x-old']!.isRemoved, isTrue);
        expect(byKey['x-new']!.isAdded, isTrue);
        expect(byKey['etag']!.isChanged, isTrue);
      },
    );

    test(
      'tooLarge short-circuits when either body exceeds the threshold',
      () async {
        final huge = 'x' * (kLargeResponseViewerChars + 1);
        final model = await ResponseDiffBuilder.build(
          _resp(body: huge),
          _resp(body: 'small'),
        );
        expect(model.tooLarge, isTrue);
        expect(model.bodyLines, isEmpty);
        // Status + header summary still populated.
        expect(model.leftStatus, 200);
      },
    );

    test('responseFromConfig reconstructs a response from saved columns', () {
      const config = HttpRequestConfigEntity(
        id: 'cfg',
        url: 'https://api.example.com/users',
        statusCode: 201,
        responseBody: '{"ok":true}',
        responseHeaders: {'X-Test': '1'},
        durationMs: 42,
      );
      final r = responseFromConfig(config);
      expect(r, isNotNull);
      expect(r!.statusCode, 201);
      expect(r.body, '{"ok":true}');
      expect(r.headers, const {'X-Test': '1'});
      expect(r.durationMs, 42);
    });

    test('responseFromConfig returns null when statusCode is absent', () {
      const config = HttpRequestConfigEntity(id: 'cfg');
      expect(responseFromConfig(config), isNull);
    });
  });
}

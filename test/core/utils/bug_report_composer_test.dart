// Tests for BugReportComposer: masking-before-resolution security contract,
// response status/duration/size line + headers block, and body-truncation
// edges (under/at/over the 50 KB cap, empty body placeholder).
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/bug_report_composer.dart';

void main() {
  const config = HttpRequestConfigEntity(
    id: 'cfg',
    method: 'POST',
    url: 'https://{{host}}/login',
    headers: {'X-Token': 'Bearer {{token}}'},
    body: '{"user":"{{user}}"}',
  );

  const response = HttpResponseEntity(
    statusCode: 200,
    body: '{"ok":true}',
    headers: {'content-type': 'application/json'},
    durationMs: 34,
  );

  const vars = {
    'host': 'api.example.com',
    'token': 'super-secret-token',
    'user': 'thiago',
  };

  group('masking', () {
    test('secret-sourced values are masked as •••; others resolve', () {
      final out = BugReportComposer.compose(
        config: config,
        response: response,
        variables: vars,
        secretKeys: const {'token'},
      );
      expect(out, contains('### POST https://api.example.com/login'));
      expect(out, contains('X-Token: Bearer •••'));
      expect(out, contains('"user":"thiago"'));
      expect(out, isNot(contains('super-secret-token')));
      expect(out, isNot(contains('{{host}}')));
    });

    test('unknown variables stay verbatim (resolver contract)', () {
      final out = BugReportComposer.compose(
        config: config,
        response: response,
        variables: const {'host': 'api.example.com'},
      );
      expect(out, contains('{{token}}'));
    });
  });

  group('response line + headers block', () {
    test('status · duration · size line and header lines', () {
      final out = BugReportComposer.compose(
        config: config,
        response: response,
        variables: vars,
      );
      // 11 UTF-8 bytes of '{"ok":true}'.
      expect(out, contains('**Response:** 200 · 34 ms · 11 B'));
      expect(out, contains('content-type: application/json'));
    });

    test('headers block omitted when the response has no headers', () {
      final out = BugReportComposer.compose(
        config: config,
        response: const HttpResponseEntity(
          statusCode: 204,
          body: '',
          headers: {},
          durationMs: 5,
        ),
        variables: vars,
      );
      expect(out, contains('**Response:** 204 · 5 ms ·'));
      // The shared `config` fixture's own request header ("X-Token: Bearer
      // …") legitimately renders inside the curl block with a "key: value"
      // shape, so a literal `isNot(contains(': '))` would false-fail on the
      // curl block itself — not on the (correctly omitted) response-headers
      // block under test here. Assert precisely instead: with response
      // headers empty AND an empty response body (no body fence either),
      // the only fenced block in the whole bundle is the curl one — exactly
      // one open + one close ``` fence, none for a response-headers block.
      expect('```'.allMatches(out).length, 2);
    });
  });

  group('body block', () {
    test('under the cap: full body, no truncation note', () {
      final out = BugReportComposer.compose(
        config: config,
        response: response,
        variables: vars,
      );
      expect(out, contains('{"ok":true}'));
      expect(out, isNot(contains('(truncated:')));
    });

    test('over 50 KB: truncated with full-size note, tail dropped', () {
      final body =
          'a' * BugReportComposer.kBugReportBodyMaxChars + 'TAIL-SENTINEL';
      final out = BugReportComposer.compose(
        config: config,
        response: HttpResponseEntity(
          statusCode: 200,
          body: body,
          headers: const {},
          durationMs: 34,
        ),
        variables: vars,
      );
      expect(
        out,
        contains('(truncated: full size ${body.length} chars)'),
      );
      expect(out, isNot(contains('TAIL-SENTINEL')));
    });

    test('exactly at the cap: no truncation note', () {
      final body = 'a' * BugReportComposer.kBugReportBodyMaxChars;
      final out = BugReportComposer.compose(
        config: config,
        response: HttpResponseEntity(
          statusCode: 200,
          body: body,
          headers: const {},
          durationMs: 34,
        ),
        variables: vars,
      );
      expect(out, isNot(contains('(truncated:')));
    });

    test('empty body renders the placeholder line', () {
      final out = BugReportComposer.compose(
        config: config,
        response: const HttpResponseEntity(
          statusCode: 204,
          body: '',
          headers: {},
          durationMs: 5,
        ),
        variables: vars,
      );
      expect(out, contains('_(empty body)_'));
    });
  });
}

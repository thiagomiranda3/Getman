import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/domain/logic/body_completion.dart';

BodyCompletionTarget? target(
  String marked, {
  bool explicit = false,
  bool fieldsEnabled = true,
}) {
  final caret = marked.indexOf('|');
  return detectBodyCompletion(
    marked.replaceFirst('|', ''),
    caret,
    explicit: explicit,
    fieldsEnabled: fieldsEnabled,
  );
}

String complete(String marked, String name, {bool explicit = false}) {
  final result = target(marked, explicit: explicit)!;
  return marked
      .replaceFirst('|', '')
      .replaceRange(
        result.replaceStart,
        result.replaceEnd,
        result.insertion(name),
      );
}

void main() {
  group('JSON property completion', () {
    test('automatically completes unquoted property prefixes', () {
      final result = target('{sess|}')!;
      expect(result.kind, BodyCompletionKind.field);
      expect(result.query, 'sess');
      expect(complete('{sess|}', 'sessionId'), '{"sessionId": }');
      expect(complete('{sess|', 'sessionId'), '{"sessionId": ');
    });
    test(
      'unquoted completion preserves suffix boundaries and existing values',
      () {
        expect(
          complete('{sess|ion : "value"}', 'sessionId'),
          '{"sessionId" : "value"}',
        );
        expect(
          complete('{sess|": 42}', 'sessionId'),
          '{"sessionId": 42}',
        );
        expect(complete('{sess|"}', 'sessionId'), '{"sessionId": }');
      },
    );
    test('finds unquoted prefixes in nested and multiline property slots', () {
      expect(
        complete('{"items": [{"id": 1, sess|}]}', 'sessionId'),
        '{"items": [{"id": 1, "sessionId": }]}',
      );
      expect(
        complete('{\n  sess|: 42\n}', 'sessionId'),
        '{\n  "sessionId": 42\n}',
      );
      expect(complete('{sessã|}', 'sessão'), '{"sessão": }');
    });
    test('escapes selected fields when replacing an unquoted prefix', () {
      expect(complete('{a|}', 'a"b\\c\n'), r'{"a\"b\\c\n": }');
    });
    test(
      'replaces the entire key while preserving existing colon and value',
      () {
        final result = target('{"na|me": 42}')!;
        expect(result.kind, BodyCompletionKind.field);
        expect(result.query, 'na');
        expect(complete('{"na|me": 42}', 'title'), '{"title": 42}');
      },
    );
    test('adds missing colon without duplicating an auto-paired quote', () {
      expect(complete('{"na|"}', 'name'), '{"name": }');
      expect(complete('{"|"}', 'name'), '{"name": }');
      expect(complete('{"na|', 'name'), '{"name": ');
    });
    test('escapes selected keys as JSON', () {
      expect(complete('{"a|"}', 'a"b\\c\n'), r'{"a\"b\\c\n": }');
    });
    test('finds property positions in nested objects and array items', () {
      expect(
        target('{"items": [{"a": 1}, {"na|"}]}')?.kind,
        BodyCompletionKind.field,
      );
      expect(target('{"items": [1, {"child": {"na|"}}]}')?.query, 'na');
      expect(target('{"a": [], "na|"}')?.query, 'na');
    });
    test('requires explicit activation at empty property positions', () {
      // Empty contexts are intentionally explicit per body autocomplete design.
      expect(target('{ |}'), isNull);
      expect(target('{"a": 1, |}'), isNull);
      expect(complete('{ |}', 'name', explicit: true), '{ "name": }');
      expect(
        complete('{"a": 1, |}', 'name', explicit: true),
        '{"a": 1, "name": }',
      );
    });
    test('ignores braces and escaped quotes in string values', () {
      expect(target(r'{"x":"a\" { , }", "na|"}')?.query, 'na');
    });
    test('never interprets ordinary values as property names', () {
      // Suggestions distinguish property keys from values by syntax.
      for (final input in [
        '{"x":"na|"}',
        '{"x":na|}',
        '[na|]',
        'na|',
        '{"x": |}',
        '["na|"]',
        '{"x":tru|e}',
        '{"x" |: 1}',
      ]) {
        expect(target(input), isNull, reason: input);
      }
    });
    test('rejects malformed or ambiguous object syntax', () {
      for (final input in [
        '{"x": 1 na|}',
        '{previous: 1, na|}',
        "{'na|}",
        '{//na|}',
        r'{\na|}',
        '{"x" "na|"}',
        '{"x": 1 "na|"}',
        '{["na|"}',
        '{"x": wrong, "na|"}',
        r'{"bad\q": 1, "na|"}',
      ]) {
        expect(target(input), isNull, reason: input);
      }
    });
    test('template values do not change the JSON container stack', () {
      expect(target('{"x": {{user id}}, "na|"}')?.query, 'na');
      expect(target('{"x": "{{user id}}", "na|"}')?.query, 'na');
    });
  });
  group('variable completion', () {
    test('supports names with spaces, punctuation, and existing suffixes', () {
      final result = target('{"x":"{{user @|domain name}}"}')!;
      expect(result.kind, BodyCompletionKind.variable);
      expect(result.query, 'user @');
      expect(
        complete('{"x":"{{user @|domain name}}"}', 'other value'),
        '{"x":"{{other value}}"}',
      );
    });
    test('replaces open placeholders without consuming surrounding syntax', () {
      expect(complete('{"x":"{{us|"}', 'user'), '{"x":"{{user}}"}');
      expect(complete('{{us|', 'user'), '{{user}}');
      expect(
        complete('query { user(id: "{{us|er}}") { id } }', 'user'),
        'query { user(id: "{{user}}") { id } }',
      );
    });
    test('incomplete unquoted placeholders preserve surrounding syntax', () {
      expect(complete('[{{us|, 42]', 'user'), '[{{user}}, 42]');
      expect(
        complete('{"id":{{us|,"other":42}', 'user'),
        '{"id":{{user}},"other":42}',
      );
      expect(
        complete('query { user(id: {{us|) { id } }', 'user'),
        'query { user(id: {{user}}) { id } }',
      );
      expect(complete('[{{us|er   , 42]', 'user'), '[{{user}}   , 42]');
    });
    test('paired variables retain wide names containing punctuation', () {
      expect(
        complete('[{{user @|domain, group: (staff)}}]', 'user'),
        '[{{user}}]',
      );
    });
    test(
      'explicit invocation inserts variables at values and raw positions',
      () {
        final result = target('{"x":"hello |world"}', explicit: true)!;
        expect(result.kind, BodyCompletionKind.variable);
        expect(result.query, '');
        expect(
          complete('{"x":"hello |world"}', 'user', explicit: true),
          '{"x":"hello {{user}}world"}',
        );
        expect(
          target('{"x": |}', explicit: true)?.kind,
          BodyCompletionKind.variable,
        );
        expect(
          target(
            'query { user(|) }',
            explicit: true,
            fieldsEnabled: false,
          )?.kind,
          BodyCompletionKind.variable,
        );
      },
    );
    test('field disablement preserves variable support', () {
      expect(target('{"na|"}', fieldsEnabled: false), isNull);
      expect(target('raw {{us|er}}', fieldsEnabled: false)?.query, 'us');
    });
    test('explicit activation inside primitive values offers variables', () {
      expect(
        target('{"x": 12|34}', explicit: true)?.kind,
        BodyCompletionKind.variable,
      );
      expect(
        target('{"x": tr|ue}', explicit: true)?.query,
        '',
      );
    });
    test(
      'completed and malformed placeholders do not trigger automatically',
      () {
        expect(target('{{user}}|'), isNull);
        expect(target('{{user\nname|'), isNull);
        expect(target('{{user{na|'), isNull);
      },
    );
  });
  test('uses UTF-16 offsets and rejects invalid caret positions', () {
    expect(complete('{"😀": 1, "na|me": 2}', 'title'), '{"😀": 1, "title": 2}');
    expect(detectBodyCompletion('{}', -1), isNull);
    expect(detectBodyCompletion('{}', 3), isNull);
  });
}

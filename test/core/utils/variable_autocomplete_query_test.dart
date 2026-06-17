import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/variable_autocomplete_query.dart';

void main() {
  group('detectActiveVariableQuery', () {
    test('empty query right after "{{"', () {
      final q = detectActiveVariableQuery('https://{{', 10);
      expect(q, isNotNull);
      expect(q!.query, '');
      expect(q.replaceStart, 10);
      expect(q.replaceEnd, 10);
      expect(q.hasClosingBraces, isFalse);
    });

    test('partial name', () {
      final q = detectActiveVariableQuery('{{ba', 4);
      expect(q!.query, 'ba');
      expect(q.replaceStart, 2);
      expect(q.replaceEnd, 4);
    });

    test('caret inside an already-closed token reports hasClosingBraces', () {
      final q = detectActiveVariableQuery('{{ba}}', 4); // caret before "}}"
      expect(q!.query, 'ba');
      expect(q.hasClosingBraces, isTrue);
    });

    test('caret after a closed token => no active query', () {
      expect(detectActiveVariableQuery('{{ab}}', 6), isNull);
    });

    test('a space (non-identifier char) ends the token', () {
      expect(detectActiveVariableQuery('{{ab cd', 7), isNull);
    });

    test('dynamic var with leading \$', () {
      final q = detectActiveVariableQuery(r'{{$gu', 5);
      expect(q!.query, r'$gu');
    });

    test('uses the nearest "{{" and ignores an earlier closed token', () {
      final q = detectActiveVariableQuery('{{a}}/{{b', 9);
      expect(q!.query, 'b');
      expect(q.replaceStart, 8);
    });

    test('single "{" is not a trigger', () {
      expect(detectActiveVariableQuery('{a', 2), isNull);
    });

    test('caret before any "{{" => null', () {
      expect(detectActiveVariableQuery('abc', 2), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/fuzzy_matcher.dart';

void main() {
  group('score', () {
    test('empty query matches everything with score 0', () {
      expect(FuzzyMatcher.score('', 'anything'), 0);
    });

    test('subsequence matches (case-insensitive)', () {
      expect(FuzzyMatcher.score('lgn', 'Login'), isNotNull);
      expect(FuzzyMatcher.score('LOGIN', 'login'), isNotNull);
    });

    test('non-subsequence returns null', () {
      expect(FuzzyMatcher.score('xyz', 'Login'), isNull);
      expect(FuzzyMatcher.score('nigol', 'Login'), isNull); // order matters
    });

    test('a contiguous prefix scores higher than a scattered match', () {
      final prefix = FuzzyMatcher.score('log', 'Login')!;
      final scattered = FuzzyMatcher.score('log', 'Catalog')!;
      expect(prefix, greaterThan(scattered));
    });
  });

  group('filter', () {
    final items = ['Login', 'Logout', 'Catalog', 'Refresh Token'];

    test('empty query returns all in original order', () {
      expect(FuzzyMatcher.filter('', items, (s) => s), items);
    });

    test('ranks the best match first', () {
      final result = FuzzyMatcher.filter('log', items, (s) => s);
      expect(result.first, anyOf('Login', 'Logout'));
      expect(result, isNot(contains('Refresh Token')));
    });

    test('drops non-matches', () {
      final result = FuzzyMatcher.filter('token', items, (s) => s);
      expect(result, ['Refresh Token']);
    });
  });
}

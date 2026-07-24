// Unit tests for buildUrlSuggestions (B4 URL autocomplete): min-chars gate,
// case-insensitive contains matching, history-before-collections and
// prefix-above-substring ranking, dedupe, self-match exclusion, cap.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/url_suggestion_source.dart';

void main() {
  group('buildUrlSuggestions', () {
    test('returns empty below kUrlSuggestionMinChars trimmed characters', () {
      expect(
        buildUrlSuggestions(
          query: 'ap',
          historyUrls: const ['https://api.dev/users'],
          collectionUrls: const [],
        ),
        isEmpty,
      );
      expect(
        buildUrlSuggestions(
          query: '  ap ',
          historyUrls: const ['https://api.dev/users'],
          collectionUrls: const [],
        ),
        isEmpty,
        reason: 'surrounding whitespace must not count toward the minimum',
      );
    });

    test('matches are case-insensitive contains', () {
      final out = buildUrlSuggestions(
        query: 'API.DEV',
        historyUrls: const ['https://api.dev/users', 'https://other.dev/x'],
        collectionUrls: const [],
      );
      expect(out, ['https://api.dev/users']);
    });

    test('history URLs (newest first) rank before collection URLs', () {
      final out = buildUrlSuggestions(
        query: 'dev',
        historyUrls: const ['https://newest.dev/a', 'https://older.dev/b'],
        collectionUrls: const ['https://saved.dev/c'],
      );
      expect(out, [
        'https://newest.dev/a',
        'https://older.dev/b',
        'https://saved.dev/c',
      ]);
    });

    test(
      'prefix matches rank above substring matches, stable within rank',
      () {
        final out = buildUrlSuggestions(
          query: 'https://api',
          historyUrls: const [
            'https://redirect.dev/?to=https://api.dev',
            'https://api.dev/users',
          ],
          collectionUrls: const ['https://api.dev/items'],
        );
        expect(out, [
          'https://api.dev/users',
          'https://api.dev/items',
          'https://redirect.dev/?to=https://api.dev',
        ]);
      },
    );

    test('dedupes — the first (history) occurrence wins', () {
      final out = buildUrlSuggestions(
        query: 'api',
        historyUrls: const ['https://api.dev/users'],
        collectionUrls: const ['https://api.dev/users', 'https://api.dev/b'],
      );
      expect(out, ['https://api.dev/users', 'https://api.dev/b']);
    });

    test('a candidate equal to the query itself is dropped', () {
      final out = buildUrlSuggestions(
        query: 'https://api.dev/users',
        historyUrls: const [
          'https://api.dev/users',
          'https://api.dev/users/1',
        ],
        collectionUrls: const [],
      );
      expect(out, ['https://api.dev/users/1']);
    });

    test('blank and whitespace-only candidates are skipped', () {
      final out = buildUrlSuggestions(
        query: 'api',
        historyUrls: const ['', '   ', 'https://api.dev/users'],
        collectionUrls: const [],
      );
      expect(out, ['https://api.dev/users']);
    });

    test('caps at kUrlSuggestionMaxResults', () {
      final history = [for (var i = 0; i < 20; i++) 'https://api.dev/$i'];
      final out = buildUrlSuggestions(
        query: 'api',
        historyUrls: history,
        collectionUrls: const [],
      );
      expect(out, hasLength(kUrlSuggestionMaxResults));
      expect(out.first, 'https://api.dev/0');
    });

    test('constants match the spec (>=3 chars, cap 8)', () {
      expect(kUrlSuggestionMinChars, 3);
      expect(kUrlSuggestionMaxResults, 8);
    });
  });
}

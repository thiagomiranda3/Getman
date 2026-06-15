import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/json_file_io.dart';

void main() {
  group('slugFilename', () {
    test(
      'lowercases and replaces non-alphanumeric runs with single underscores',
      () {
        expect(slugFilename('My API Collection'), 'my_api_collection');
        expect(slugFilename('Prod (EU) — v2!'), 'prod_eu_v2');
      },
    );

    test('trims leading and trailing underscores', () {
      expect(slugFilename('  --Staging-- '), 'staging');
    });

    test('falls back to "untitled" when nothing survives', () {
      expect(slugFilename('***'), 'untitled');
      expect(slugFilename(''), 'untitled');
    });
  });

  group('importSummaryMessage', () {
    test('reports a plain success count when nothing failed', () {
      expect(
        importSummaryMessage(
          importedCount: 2,
          failures: const [],
          noun: 'collection',
        ),
        'Imported 2 collection(s).',
      );
    });

    test('reports failure-only imports', () {
      expect(
        importSummaryMessage(
          importedCount: 0,
          failures: const ['a.json: bad'],
          noun: 'collection',
        ),
        'Import failed: a.json: bad',
      );
    });

    test('reports partial success with skipped files', () {
      expect(
        importSummaryMessage(
          importedCount: 1,
          failures: const ['a.json: bad', 'b.json: worse'],
          noun: 'environment',
        ),
        'Imported 1 environment(s). Skipped: a.json: bad; b.json: worse',
      );
    });

    test('returns null when there is nothing to report', () {
      expect(
        importSummaryMessage(
          importedCount: 0,
          failures: const [],
          noun: 'collection',
        ),
        isNull,
      );
    });
  });
}

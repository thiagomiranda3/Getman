import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late Box<HttpRequestConfig> box;
  late HistoryLocalDataSourceImpl dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_history_ds_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(HttpRequestConfigAdapter());
    }
    box = await Hive.openBox<HttpRequestConfig>(HiveBoxes.history);
    dataSource = HistoryLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  HttpRequestConfig makeConfig({
    String method = 'GET',
    String url = 'https://example.com',
    String body = '',
    Map<String, String>? headers,
  }) => HttpRequestConfig(
    method: method,
    url: url,
    body: body,
    headers: headers ?? {},
  );

  group('addToHistory – dedup', () {
    test(
      'same method+url+body is deduplicated: only one entry remains, '
      'moved to newest position',
      () async {
        final first = makeConfig(url: 'https://a.com');
        final second = makeConfig(url: 'https://b.com');
        final duplicate = makeConfig(
          url: 'https://a.com',
        ); // same signature as first

        await dataSource.addToHistory(first, 10);
        await dataSource.addToHistory(second, 10);
        await dataSource.addToHistory(
          duplicate,
          10,
        ); // should evict first, re-insert at end

        final history = await dataSource.getHistory();
        expect(history, hasLength(2));
        // The deduplicated entry should be last (newest).
        expect(history.last.url, 'https://a.com');
        expect(history.first.url, 'https://b.com');
      },
    );

    test(
      'different headers on same method+url+body ARE deduplicated — '
      'headers are not part of the dedup key',
      () async {
        // Headers are intentionally excluded from the dedup signature per
        // CLAUDE.md §4.4. Two requests that differ only in headers share the
        // same method+url+body signature and are therefore treated as the
        // same logical request.
        final withAccept = makeConfig(
          url: 'https://api.example.com',
          headers: {'Accept': 'application/json'},
        );
        final withBearer = makeConfig(
          url: 'https://api.example.com',
          headers: {'Authorization': 'Bearer token'},
        );

        await dataSource.addToHistory(withAccept, 10);
        await dataSource.addToHistory(withBearer, 10);

        // Both share the same signature; the second replaces the first → 1
        // entry.
        final history = await dataSource.getHistory();
        expect(history, hasLength(1));
      },
    );

    test(
      'two different configs (different URLs) both remain in the box',
      () async {
        final configA = makeConfig(url: 'https://service-a.com/endpoint');
        final configB = makeConfig(url: 'https://service-b.com/endpoint');

        await dataSource.addToHistory(configA, 10);
        await dataSource.addToHistory(configB, 10);

        final history = await dataSource.getHistory();
        expect(history, hasLength(2));
      },
    );

    test(
      'two different configs (different methods) both remain in the box',
      () async {
        final getReq = makeConfig();
        final postReq = makeConfig(method: 'POST');

        await dataSource.addToHistory(getReq, 10);
        await dataSource.addToHistory(postReq, 10);

        final history = await dataSource.getHistory();
        expect(history, hasLength(2));
      },
    );
  });

  group('addToHistory – trim', () {
    test('respects the given limit', () async {
      for (var i = 0; i < 5; i++) {
        await dataSource.addToHistory(makeConfig(url: 'https://req-$i.com'), 3);
      }

      final history = await dataSource.getHistory();
      expect(history, hasLength(3));
    });

    test('actually shrinks below a lowered limit when called again', () async {
      // Fill to 5 entries.
      for (var i = 0; i < 5; i++) {
        await dataSource.addToHistory(
          makeConfig(url: 'https://item-$i.com'),
          10,
        );
      }
      expect(box.length, 5);

      // Adding one more entry with limit=3 should trim to 3.
      await dataSource.addToHistory(makeConfig(url: 'https://new.com'), 3);

      expect(box.length, 3);
    });

    test(
      'dedup-evict and trim in the same add still honor the limit',
      () async {
        // Fill 4 distinct entries.
        for (var i = 0; i < 4; i++) {
          await dataSource.addToHistory(
            makeConfig(url: 'https://d-$i.com'),
            10,
          );
        }
        // Re-adding d-1 evicts the old d-1 (dedup) AND limit=2 trims, in one
        // call.
        await dataSource.addToHistory(makeConfig(url: 'https://d-1.com'), 2);

        final history = await dataSource.getHistory();
        expect(history, hasLength(2));
        expect(history.last.url, 'https://d-1.com'); // re-inserted as newest
      },
    );

    test('oldest entries are trimmed, newest are kept', () async {
      for (var i = 0; i < 4; i++) {
        await dataSource.addToHistory(
          makeConfig(url: 'https://old-$i.com'),
          10,
        );
      }
      await dataSource.addToHistory(makeConfig(url: 'https://newest.com'), 3);

      final history = await dataSource.getHistory();
      expect(history.last.url, 'https://newest.com');
      // Oldest entry should be gone.
      expect(history.any((c) => c.url == 'https://old-0.com'), isFalse);
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/data/repositories/history_repository_impl.dart';
import 'package:hive_ce/hive.dart';

class _FakeHistoryDataSource implements HistoryLocalDataSource {
  // Test-only broadcast controller; each test cancels its subscription or uses
  // .first — no genuine resource leak (broadcast controllers buffer nothing).
  // ignore: close_sinks
  final StreamController<void> controller = StreamController<void>.broadcast();
  int reads = 0;
  List<HttpRequestConfig> data = [];
  final List<HttpRequestConfig> added = [];

  @override
  Future<List<HttpRequestConfig>> getHistory() async {
    reads++;
    return data;
  }

  @override
  Future<void> addToHistory(HttpRequestConfig config, int limit) async {
    added.add(config);
  }

  @override
  Stream<void> watch() => controller.stream;

  final List<String> deletedIds = [];
  bool cleared = false;
  final List<HttpRequestConfig> restored = [];

  @override
  Future<void> deleteFromHistory(String id) async {
    deletedIds.add(id);
  }

  @override
  Future<void> clearHistory() async {
    cleared = true;
  }

  @override
  Future<void> restoreToHistory(List<HttpRequestConfig> configs) async {
    restored.addAll(configs);
  }
}

void main() {
  test(
    'watchHistory coalesces a burst of watch events into one re-read',
    () async {
      final ds = _FakeHistoryDataSource()
        ..data = [HttpRequestConfig(id: 'a', url: 'https://a.dev')];
      final repo = HistoryRepositoryImpl(ds);

      final emissions = <List<HttpRequestConfigEntity>>[];
      final sub = repo.watchHistory().listen(emissions.add);
      await Future<void>.delayed(Duration.zero); // initial snapshot

      // One addToHistory fires ~3 box events (dedup delete + add + batched
      // trim).
      ds.controller.add(null);
      ds.controller.add(null);
      ds.controller.add(null);
      await Future<void>.delayed(
        const Duration(milliseconds: 150),
      ); // past coalesce window
      await sub.cancel();

      // Initial read + a single coalesced read — NOT 1 + 3.
      expect(ds.reads, 2);
      expect(emissions, hasLength(2));
      expect(emissions.last.single.url, 'https://a.dev');
    },
  );

  test('watchHistory emits an initial snapshot on subscribe', () async {
    final ds = _FakeHistoryDataSource()
      ..data = [HttpRequestConfig(id: 'a', url: 'https://a.dev')];
    final repo = HistoryRepositoryImpl(ds);

    final first = await repo.watchHistory().first;
    expect(first.single.url, 'https://a.dev');
  });

  test('addToHistory stamps sentAt with the injected clock', () async {
    final ds = _FakeHistoryDataSource();
    final fixed = DateTime(2026, 7, 24, 9);
    final repo = HistoryRepositoryImpl(ds, now: () => fixed);

    await repo.addToHistory(
      const HttpRequestConfigEntity(id: 'a', url: 'https://a.dev'),
      10,
    );

    expect(ds.added, hasLength(1));
    expect(ds.added.single.sentAt, fixed);
  });

  test(
    'watchHistory sorts newest-first by sentAt with legacy (null) entries last',
    () async {
      final ds = _FakeHistoryDataSource()
        ..data = [
          HttpRequestConfig(id: 'legacy', url: 'https://legacy.dev'),
          HttpRequestConfig(id: 'old', url: 'https://old.dev')
            ..sentAt = DateTime(2026, 7, 20),
          HttpRequestConfig(id: 'new', url: 'https://new.dev')
            ..sentAt = DateTime(2026, 7, 24),
        ];
      final repo = HistoryRepositoryImpl(ds);

      final list = await repo.watchHistory().first;
      expect(list.map((e) => e.id), ['new', 'old', 'legacy']);
    },
  );

  test(
    'deleteHistoryEntry / clearHistory / restoreHistoryEntries delegate to '
    'the data source; restore preserves the snapshot sentAt (no re-stamp)',
    () async {
      final ds = _FakeHistoryDataSource();
      final repo = HistoryRepositoryImpl(ds);

      await repo.deleteHistoryEntry('id-1');
      expect(ds.deletedIds, ['id-1']);

      await repo.clearHistory();
      expect(ds.cleared, isTrue);

      final snapshot = HttpRequestConfigEntity(
        id: 'r',
        url: 'https://r.dev',
        sentAt: DateTime(2026, 7, 20),
      );
      await repo.restoreHistoryEntries([snapshot]);
      expect(ds.restored.single.id, 'r');
      expect(ds.restored.single.sentAt, DateTime(2026, 7, 20));
    },
  );

  group(
    'D3 critical fix: unique id per history record (delete targets exactly '
    'one row) — real Hive-backed data source, not the fake',
    () {
      late Directory tempDir;
      late HistoryLocalDataSourceImpl realDataSource;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'getman_history_repo_id_test',
        );
        Hive.init(tempDir.path);
        if (!Hive.isAdapterRegistered(1)) {
          Hive.registerAdapter(HttpRequestConfigAdapter());
        }
        await Hive.openBox<HttpRequestConfig>(HiveBoxes.history);
        realDataSource = HistoryLocalDataSourceImpl();
      });

      tearDown(() async {
        await Hive.deleteFromDisk();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      test(
        'two addToHistory calls from the SAME source id (a tab '
        'edited-and-resent — different urls) produce rows with DISTINCT '
        'minted ids, and both survive',
        () async {
          final repo = HistoryRepositoryImpl(realDataSource);

          await repo.addToHistory(
            const HttpRequestConfigEntity(id: 'tab-1', url: 'https://a.dev'),
            10,
          );
          await repo.addToHistory(
            const HttpRequestConfigEntity(id: 'tab-1', url: 'https://b.dev'),
            10,
          );

          final stored = await realDataSource.getHistory();
          expect(stored, hasLength(2));
          expect(stored[0].id, isNot(stored[1].id));
        },
      );

      test(
        'deleteHistoryEntry(rowB.id) removes exactly rowB — the sibling '
        'row minted from the same source id is untouched',
        () async {
          final repo = HistoryRepositoryImpl(realDataSource);

          await repo.addToHistory(
            const HttpRequestConfigEntity(id: 'tab-1', url: 'https://a.dev'),
            10,
          );
          await repo.addToHistory(
            const HttpRequestConfigEntity(id: 'tab-1', url: 'https://b.dev'),
            10,
          );

          final rowB = (await realDataSource.getHistory()).firstWhere(
            (c) => c.url == 'https://b.dev',
          );

          await repo.deleteHistoryEntry(rowB.id);

          final remaining = await realDataSource.getHistory();
          expect(remaining, hasLength(1));
          expect(remaining.single.url, 'https://a.dev');
        },
      );

      test(
        'restoreHistoryEntries keeps the captured id verbatim — undo must '
        'reinsert the exact deleted record, not a re-minted one',
        () async {
          final repo = HistoryRepositoryImpl(realDataSource);

          await repo.addToHistory(
            const HttpRequestConfigEntity(id: 'tab-1', url: 'https://a.dev'),
            10,
          );
          final before = await realDataSource.getHistory();
          final mintedId = before.single.id;
          final snapshot = before.single.toEntity();

          await repo.deleteHistoryEntry(mintedId);
          expect(await realDataSource.getHistory(), isEmpty);

          await repo.restoreHistoryEntries([snapshot]);

          final restored = await realDataSource.getHistory();
          expect(restored.single.id, mintedId);
        },
      );
    },
  );
}

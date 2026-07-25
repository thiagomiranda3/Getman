import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/data/repositories/history_repository_impl.dart';

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
}

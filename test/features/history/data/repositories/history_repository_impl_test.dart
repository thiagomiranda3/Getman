import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/data/repositories/history_repository_impl.dart';

class _FakeHistoryDataSource implements HistoryLocalDataSource {
  final StreamController<void> controller = StreamController<void>.broadcast();
  int reads = 0;
  List<HttpRequestConfig> data = [];

  @override
  Future<List<HttpRequestConfig>> getHistory() async {
    reads++;
    return data;
  }

  @override
  Future<void> addToHistory(HttpRequestConfig config, int limit) async {}

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
}

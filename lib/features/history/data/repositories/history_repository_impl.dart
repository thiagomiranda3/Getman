// HistoryRepository impl over HistoryLocalDataSource. watchHistory() debounces
// the data source's raw Box.watch() events (a single addToHistory can fire up
// to ~3 mutations) within an 80ms coalescing window so subscribers see one
// re-read + emission per burst, not one per mutation; the emitted list is
// ordered by a stable mergeSort on sentAt descending (nulls/legacy rows
// last), with the pre-sort `.reversed` (box insertion order) acting as the
// tie-break for entries with equal or missing timestamps.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/error/guard.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl(this.localDataSource, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final HistoryLocalDataSource localDataSource;

  /// Injectable clock so tests can pin the sentAt stamp.
  final DateTime Function() _now;

  /// One `addToHistory` performs up to ~3 box mutations (dedup delete + add +
  /// batched trim), each firing a watch event. Coalescing within this window
  /// turns that burst into a single full re-read + emission.
  static const Duration _coalesceWindow = Duration(milliseconds: 80);

  Future<List<HttpRequestConfigEntity>> _read() => guardPersistence(() async {
    final models = await localDataSource.getHistory();
    // Newest first. Reversed box insertion order is the tie-break baseline; a
    // STABLE mergeSort by sentAt then overlays chronological order so
    // restored entries (appended at the box tail by an UNDO) land back at
    // their original slot. Legacy records without sentAt sink below all
    // dated ones (they group under the EARLIER day header).
    final entities = models.reversed.map((m) => m.toEntity()).toList();
    mergeSort<HttpRequestConfigEntity>(entities, compare: _bySentAtDesc);
    return entities;
  });

  static int _bySentAtDesc(
    HttpRequestConfigEntity a,
    HttpRequestConfigEntity b,
  ) {
    final at = a.sentAt;
    final bt = b.sentAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  @override
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit) =>
      guardPersistence(() async {
        await localDataSource.addToHistory(
          // Stamp the send time here (the data layer owns wall-clock
          // concerns). Dedup ignores sentAt by design, so a re-send of the
          // same request refreshes the stamp.
          HttpRequestConfig.fromEntity(config)..sentAt = _now(),
          limit,
        );
      });

  @override
  Stream<List<HttpRequestConfigEntity>> watchHistory() {
    StreamSubscription<void>? sub;
    Timer? debounce;
    // Ownership-transfer: onCancel closes the controller when the subscriber
    // cancels.
    late StreamController<List<HttpRequestConfigEntity>> controller;

    Future<void> push() async {
      try {
        final list = await _read();
        if (!controller.isClosed) controller.add(list);
      } on Object catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller = StreamController<List<HttpRequestConfigEntity>>(
      onListen: () {
        unawaited(push()); // initial snapshot on subscribe
        sub = localDataSource.watch().listen((_) {
          debounce?.cancel();
          debounce = Timer(_coalesceWindow, push);
        });
      },
      onCancel: () async {
        debounce?.cancel();
        await sub?.cancel();
        // Actually close — the `// ignore: close_sinks` above promises this;
        // without it an in-flight push() buffers into a listener-less
        // controller that lives forever.
        await controller.close();
      },
    );
    return controller.stream;
  }
}

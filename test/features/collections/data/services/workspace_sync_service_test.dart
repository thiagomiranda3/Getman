import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:mocktail/mocktail.dart';

class _MockDataSource extends Mock implements WorkspaceCollectionsDataSource {}

void main() {
  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  late _MockDataSource ds;

  setUp(() {
    ds = _MockDataSource();
    when(() => ds.write(any(), any())).thenAnswer((_) async {});
    when(() => ds.read(any())).thenAnswer((_) async => const []);
  });

  test('scheduleMirror debounces bursts into a single write', () async {
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    service
      ..scheduleMirror('/ws', const [])
      ..scheduleMirror('/ws', const []); // second cancels the first
    await Future<void>.delayed(const Duration(milliseconds: 30));

    verify(() => ds.write('/ws', any())).called(1);
  });

  test('mirrored emits the root after a successful write', () async {
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    final emitted = service.mirrored.first;
    service.scheduleMirror('/ws', const []);

    await expectLater(emitted, completion('/ws'));
  });

  test('mirrored stays silent when the write fails', () async {
    when(() => ds.write(any(), any())).thenThrow(Exception('disk full'));
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    var emissions = 0;
    final sub = service.mirrored.listen((_) => emissions++);
    addTearDown(sub.cancel);

    service.scheduleMirror('/ws', const []);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(emissions, 0);
  });

  test('read delegates to the data source', () async {
    final service = WorkspaceSyncService(ds);
    addTearDown(service.dispose);

    await service.read('/ws');
    verify(() => ds.read('/ws')).called(1);
  });

  test('a write failure is swallowed (never breaks the session)', () async {
    when(() => ds.write(any(), any())).thenThrow(Exception('disk full'));
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    service.scheduleMirror('/ws', const []);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // No throw escapes; reaching here is the assertion.
  });

  test(
    'a mirror failure logs once per root, then quiets until recovery',
    () async {
      final failures = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null && message.contains('Workspace mirror failed')) {
          failures.add(message);
        }
      };
      addTearDown(() => debugPrint = original);

      final service = WorkspaceSyncService(
        ds,
        debounce: const Duration(milliseconds: 5),
      );
      addTearDown(service.dispose);

      Future<void> flush() =>
          Future<void>.delayed(const Duration(milliseconds: 20));

      // Two consecutive failures for the same root → logged only once.
      when(() => ds.write(any(), any())).thenThrow(Exception('denied'));
      service.scheduleMirror('/ws', const []);
      await flush();
      service.scheduleMirror('/ws', const []);
      await flush();
      expect(failures.length, 1);

      // A successful write re-arms logging for that root.
      when(() => ds.write(any(), any())).thenAnswer((_) async {});
      service.scheduleMirror('/ws', const []);
      await flush();

      // The next failure logs again (quieting was reset on recovery).
      when(() => ds.write(any(), any())).thenThrow(Exception('denied again'));
      service.scheduleMirror('/ws', const []);
      await flush();
      expect(failures.length, 2);
    },
  );

  test('flushPending writes a pending mirror immediately', () async {
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(seconds: 30), // would not fire on its own
    );
    addTearDown(service.dispose);

    service.scheduleMirror('/ws', const []);
    verifyNever(() => ds.write('/ws', any()));

    await service.flushPending();

    // The write must have landed *before* flushPending completes — this is
    // what lets a branch switch trust `git status`.
    verify(() => ds.write('/ws', any())).called(1);
  });

  test('flushPending is a no-op when nothing is pending', () async {
    final service = WorkspaceSyncService(ds);
    addTearDown(service.dispose);

    await service.flushPending();

    verifyNever(() => ds.write(any(), any()));
  });

  test('flushPending does not write twice when the timer also fires', () async {
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    service.scheduleMirror('/ws', const []);
    await service.flushPending();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    verify(() => ds.write('/ws', any())).called(1);
  });
}

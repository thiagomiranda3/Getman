// Exit must wait for debounced saves before flushing the storage worker,
// and must not acknowledge the OS until that final flush has completed.
import 'dart:async';
import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/home/presentation/widgets/exit_flush_guard.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class _Tabs extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _Collections extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _Workspace extends Mock implements WorkspaceSyncService {}

void main() {
  testWidgets('exit waits for pending saves and then the worker flush', (
    tester,
  ) async {
    final tabs = _Tabs();
    final collections = _Collections();
    final workspace = _Workspace();
    final tabSave = Completer<void>();
    final collectionSave = Completer<void>();
    final mirrorSave = Completer<bool>();
    final storageFlush = Completer<void>();
    when(tabs.flushPendingSaves).thenAnswer((_) => tabSave.future);
    when(
      collections.flushPendingSaves,
    ).thenAnswer((_) => collectionSave.future);
    when(workspace.flushPending).thenAnswer((_) => mirrorSave.future);
    addTearDown(tabs.close);
    addTearDown(collections.close);
    var storageStarted = false;
    var exitCompleted = false;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<CollectionsBloc>.value(value: collections),
        ],
        child: RepositoryProvider<WorkspaceSyncService>.value(
          value: workspace,
          child: ExitFlushGuard(
            flushStorage: () {
              storageStarted = true;
              return storageFlush.future;
            },
            child: const SizedBox(),
          ),
        ),
      ),
    );
    final exit = tester.binding.handleRequestAppExit().then((response) {
      exitCompleted = true;
      return response;
    });
    await tester.pump();
    expect(storageStarted, isFalse);
    expect(exitCompleted, isFalse);
    tabSave.complete();
    collectionSave.complete();
    await tester.pump();
    expect(storageStarted, isFalse, reason: 'workspace write is still pending');
    mirrorSave.complete(true);
    await tester.pump();
    expect(storageStarted, isTrue);
    expect(exitCompleted, isFalse, reason: 'Hive flush is still pending');
    storageFlush.complete();
    await tester.pump();
    expect(await exit, AppExitResponse.exit);
  });
}

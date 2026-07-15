import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';
import 'package:getman/features/collections/domain/logic/three_way_merge.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_event.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_state.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/conflict_resolution_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _MockConflictBloc extends MockBloc<ConflictEvent, ConflictState>
    implements ConflictBloc {}

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

class _FakeConflictEvent extends Fake implements ConflictEvent {}

class _FakeGitSyncEvent extends Fake implements GitSyncEvent {}

const _node = CollectionNodeEntity(
  id: 'r1',
  name: 'Get thing',
  isFolder: false,
);

void main() {
  const root = '/ws';

  setUpAll(() {
    registerFallbackValue(_FakeConflictEvent());
    registerFallbackValue(_FakeGitSyncEvent());
  });

  late _MockConflictBloc conflictBloc;
  late _MockGitSyncBloc gitBloc;

  setUp(() {
    conflictBloc = _MockConflictBloc();
    gitBloc = _MockGitSyncBloc();
    when(() => gitBloc.state).thenReturn(const GitSyncState());
  });

  Widget host() {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<ConflictBloc>.value(value: conflictBloc),
            BlocProvider<GitSyncBloc>.value(value: gitBloc),
          ],
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  ConflictResolutionDialog.show(context, root: root),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a field-level scalar conflict renders the two side buttons', (
    tester,
  ) async {
    const conflicts = [
      FileConflict(
        path: 'r1.req.json',
        kind: ConflictKind.request,
        node: NodeMergeResult(
          merged: _node,
          conflicts: [
            FieldConflict(
              field: 'url',
              kind: FieldConflictKind.scalar,
              incoming: 'https://a.example',
              yours: 'https://b.example',
            ),
          ],
        ),
      ),
    ];
    when(() => conflictBloc.state).thenReturn(
      const ConflictState(status: ConflictStatus.ready, conflicts: conflicts),
    );

    await openDialog(tester);

    expect(find.text('TAKE INCOMING'), findsOneWidget);
    expect(find.text('KEEP YOURS'), findsOneWidget);
    verify(() => conflictBloc.add(const LoadConflicts(root))).called(1);
  });

  testWidgets(
    'picking Keep Yours then RESOLVE & CONTINUE sends the yours value',
    (tester) async {
      const conflicts = [
        FileConflict(
          path: 'r1.req.json',
          kind: ConflictKind.request,
          node: NodeMergeResult(
            merged: _node,
            conflicts: [
              FieldConflict(
                field: 'url',
                kind: FieldConflictKind.scalar,
                incoming: 'https://a.example',
                yours: 'https://b.example',
              ),
            ],
          ),
        ),
      ];
      when(() => conflictBloc.state).thenReturn(
        const ConflictState(
          status: ConflictStatus.ready,
          conflicts: conflicts,
        ),
      );

      await openDialog(tester);
      await tester.tap(
        find.byKey(const ValueKey('keep_yours_r1.req.json_url')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conflict_resolve')));
      await tester.pumpAndSettle();

      verify(
        () => conflictBloc.add(
          const ResolveAndContinue(root, [
            FileResolution(
              path: 'r1.req.json',
              fieldChoices: {'url': 'https://b.example'},
            ),
          ]),
        ),
      ).called(1);
    },
  );

  testWidgets(
    "an opaque authentication conflict's pick is the literal marker, not a "
    'value',
    (tester) async {
      const conflicts = [
        FileConflict(
          path: 'r1.req.json',
          kind: ConflictKind.request,
          node: NodeMergeResult(
            merged: _node,
            conflicts: [
              FieldConflict(
                field: 'authentication',
                kind: FieldConflictKind.opaque,
              ),
            ],
          ),
        ),
      ];
      when(() => conflictBloc.state).thenReturn(
        const ConflictState(
          status: ConflictStatus.ready,
          conflicts: conflicts,
        ),
      );

      await openDialog(tester);
      await tester.tap(
        find.byKey(const ValueKey('keep_yours_r1.req.json_authentication')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conflict_resolve')));
      await tester.pumpAndSettle();

      verify(
        () => conflictBloc.add(
          const ResolveAndContinue(root, [
            FileResolution(
              path: 'r1.req.json',
              fieldChoices: {'authentication': 'yours'},
            ),
          ]),
        ),
      ).called(1);
    },
  );

  testWidgets(
    'a coarse deleteModify conflict shows the labelled choices and sets '
    'wholeFile',
    (tester) async {
      const conflicts = [
        FileConflict(
          path: 'r2.req.json',
          kind: ConflictKind.deleteModify,
        ),
      ];
      when(() => conflictBloc.state).thenReturn(
        const ConflictState(
          status: ConflictStatus.ready,
          conflicts: conflicts,
        ),
      );

      await openDialog(tester);

      expect(find.text('Accept the deletion'), findsOneWidget);
      expect(find.text('Keep your edited request'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('keep_yours_r2.req.json')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conflict_resolve')));
      await tester.pumpAndSettle();

      verify(
        () => conflictBloc.add(
          const ResolveAndContinue(root, [
            FileResolution(path: 'r2.req.json', wholeFile: FileSide.yours),
          ]),
        ),
      ).called(1);
    },
  );

  testWidgets('RESOLVE is disabled until every conflict has a pick', (
    tester,
  ) async {
    const conflicts = [
      FileConflict(
        path: 'r1.req.json',
        kind: ConflictKind.request,
        node: NodeMergeResult(
          merged: _node,
          conflicts: [
            FieldConflict(
              field: 'url',
              kind: FieldConflictKind.scalar,
              incoming: 'a',
              yours: 'b',
            ),
          ],
        ),
      ),
      FileConflict(path: 'r2.req.json', kind: ConflictKind.deleteModify),
    ];
    when(() => conflictBloc.state).thenReturn(
      const ConflictState(status: ConflictStatus.ready, conflicts: conflicts),
    );

    await openDialog(tester);

    FilledButton resolveButton() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('conflict_resolve')),
    );
    expect(resolveButton().onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('keep_yours_r1.req.json_url')),
    );
    await tester.pumpAndSettle();
    expect(resolveButton().onPressed, isNull); // r2 still unpicked

    await tester.tap(find.byKey(const ValueKey('keep_yours_r2.req.json')));
    await tester.pumpAndSettle();
    expect(resolveButton().onPressed, isNotNull);
  });

  testWidgets('an auto-merged file needs no pick and does not block RESOLVE', (
    tester,
  ) async {
    const conflicts = [
      FileConflict(
        path: 'r1.req.json',
        kind: ConflictKind.request,
        node: NodeMergeResult(merged: _node, conflicts: []),
      ),
    ];
    when(() => conflictBloc.state).thenReturn(
      const ConflictState(status: ConflictStatus.ready, conflicts: conflicts),
    );

    await openDialog(tester);

    expect(find.text('Auto-merged.'), findsOneWidget);
    final resolveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('conflict_resolve')),
    );
    expect(resolveButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('conflict_resolve')));
    await tester.pumpAndSettle();

    verify(
      () => conflictBloc.add(
        const ResolveAndContinue(root, [
          FileResolution(path: 'r1.req.json'),
        ]),
      ),
    ).called(1);
  });

  testWidgets('CANCEL dispatches AbortRebase and closes the dialog', (
    tester,
  ) async {
    when(
      () => conflictBloc.state,
    ).thenReturn(const ConflictState(status: ConflictStatus.ready));

    await openDialog(tester);
    await tester.tap(find.byKey(const ValueKey('conflict_cancel')));
    await tester.pumpAndSettle();

    verify(() => conflictBloc.add(const AbortRebase(root))).called(1);
    expect(find.byKey(const ValueKey('conflict_cancel')), findsNothing);
  });

  testWidgets('a done status closes the dialog and refreshes branch status', (
    tester,
  ) async {
    final controller = StreamController<ConflictState>();
    whenListen(
      conflictBloc,
      controller.stream,
      initialState: const ConflictState(status: ConflictStatus.ready),
    );

    await openDialog(tester);
    controller.add(const ConflictState(status: ConflictStatus.done));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('conflict_cancel')), findsNothing);
    verify(() => gitBloc.add(const LoadBranchStatus(root))).called(1);
    await controller.close();
  });

  testWidgets('an error status surfaces the GIT ERROR dialog', (
    tester,
  ) async {
    final controller = StreamController<ConflictState>();
    whenListen(
      conflictBloc,
      controller.stream,
      initialState: const ConflictState(status: ConflictStatus.ready),
    );

    await openDialog(tester);
    controller.add(
      const ConflictState(status: ConflictStatus.error, errorMessage: 'boom'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('conflict_error_dialog')), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    await controller.close();
  });
}

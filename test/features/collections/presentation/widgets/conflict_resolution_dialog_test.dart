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
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockConflictBloc extends MockBloc<ConflictEvent, ConflictState>
    implements ConflictBloc {}

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

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
  late _MockSettingsBloc settingsBloc;

  setUp(() {
    conflictBloc = _MockConflictBloc();
    gitBloc = _MockGitSyncBloc();
    when(() => gitBloc.state).thenReturn(const GitSyncState());
    settingsBloc = _MockSettingsBloc();
    when(
      () => settingsBloc.state,
    ).thenReturn(const SettingsState(settings: SettingsEntity()));
    when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget host() {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<ConflictBloc>.value(value: conflictBloc),
            BlocProvider<GitSyncBloc>.value(value: gitBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
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

  // FIX C1: the coarse deleteModify tile used to hardcode "Accept the
  // deletion" to the incoming button and "Keep your edited request" to the
  // yours button — correct only when upstream deleted (Case A). When YOU
  // deleted (Case B: stage 3 absent, deletedSide=yours), that hardcoding
  // put "Accept the deletion" on the button that actually resolves to
  // wholeFile: incoming (the PRESENT stage — writes the file back) and
  // "Keep your edited request" on the button that resolves to wholeFile:
  // yours (the ABSENT stage — deletes it): exactly inverted. These four
  // cases (both labels x both orientations) pin the fix by tapping on the
  // button *text*, not a positional key, so a regression back to hardcoded
  // labels fails loudly.
  for (final side in [FileSide.incoming, FileSide.yours]) {
    final otherSide = side == FileSide.incoming
        ? FileSide.yours
        : FileSide.incoming;
    final orientation = side == FileSide.incoming
        ? 'Case A (upstream deleted)'
        : 'Case B (you deleted)';

    testWidgets(
      '$orientation: tapping "Accept the deletion" resolves to the '
      'deleting side ($side)',
      (tester) async {
        final conflicts = [
          FileConflict(
            path: 'r2.req.json',
            kind: ConflictKind.deleteModify,
            deletedSide: side,
          ),
        ];
        when(() => conflictBloc.state).thenReturn(
          ConflictState(status: ConflictStatus.ready, conflicts: conflicts),
        );

        await openDialog(tester);
        await tester.tap(find.text('Accept the deletion'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('conflict_resolve')));
        await tester.pumpAndSettle();

        verify(
          () => conflictBloc.add(
            ResolveAndContinue(root, [
              FileResolution(path: 'r2.req.json', wholeFile: side),
            ]),
          ),
        ).called(1);
      },
    );

    testWidgets(
      '$orientation: tapping "Keep the edited request" resolves to the '
      'surviving side ($otherSide)',
      (tester) async {
        final conflicts = [
          FileConflict(
            path: 'r2.req.json',
            kind: ConflictKind.deleteModify,
            deletedSide: side,
          ),
        ];
        when(() => conflictBloc.state).thenReturn(
          ConflictState(status: ConflictStatus.ready, conflicts: conflicts),
        );

        await openDialog(tester);
        await tester.tap(find.text('Keep the edited request'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('conflict_resolve')));
        await tester.pumpAndSettle();

        verify(
          () => conflictBloc.add(
            ResolveAndContinue(root, [
              FileResolution(path: 'r2.req.json', wholeFile: otherSide),
            ]),
          ),
        ).called(1);
      },
    );
  }

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

  // FIX M1: CANCEL used to pop immediately, so an AbortRebase failure would
  // surface on a dead (deactivated) context with the rebase still in
  // progress and no UI to retry from. Now _cancel dispatches AbortRebase and
  // waits — the dialog only pops once the abort actually resolves to `done`,
  // and stays open (with the GIT ERROR dialog on top) if the abort fails.
  testWidgets(
    'CANCEL dispatches AbortRebase but keeps the dialog open until the '
    'abort resolves',
    (tester) async {
      final controller = StreamController<ConflictState>();
      whenListen(
        conflictBloc,
        controller.stream,
        initialState: const ConflictState(status: ConflictStatus.ready),
      );

      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('conflict_cancel')));
      await tester.pump();

      verify(() => conflictBloc.add(const AbortRebase(root))).called(1);
      // Still open: the abort hasn't resolved yet.
      expect(find.byKey(const ValueKey('conflict_cancel')), findsOneWidget);

      controller.add(const ConflictState(status: ConflictStatus.done));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('conflict_cancel')), findsNothing);
      await controller.close();
    },
  );

  testWidgets(
    'CANCEL does not show the "Conflicts resolved." snackbar or reload the '
    'tree when the abort resolves to done',
    (tester) async {
      final controller = StreamController<ConflictState>();
      whenListen(
        conflictBloc,
        controller.stream,
        initialState: const ConflictState(status: ConflictStatus.ready),
      );

      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('conflict_cancel')));
      await tester.pump();
      controller.add(const ConflictState(status: ConflictStatus.done));
      await tester.pump();
      await tester.pumpAndSettle();

      verify(() => conflictBloc.add(const AbortRebase(root))).called(1);
      expect(find.text('Conflicts resolved.'), findsNothing);
      verifyNever(() => gitBloc.add(const ConflictsResolved(root)));
      // Branch status IS refreshed: the post-conflict status was read
      // mid-rebase (detached HEAD → current == null), which hides the branch
      // chip until something else refreshes it.
      verify(() => gitBloc.add(const LoadBranchStatus(root))).called(1);
      await controller.close();
    },
  );

  testWidgets(
    'an AbortRebase failure surfaces the GIT ERROR dialog and leaves the '
    'resolver open for a retry',
    (tester) async {
      final controller = StreamController<ConflictState>();
      whenListen(
        conflictBloc,
        controller.stream,
        initialState: const ConflictState(status: ConflictStatus.ready),
      );

      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('conflict_cancel')));
      await tester.pump();
      controller.add(
        const ConflictState(
          status: ConflictStatus.error,
          errorMessage: 'abort failed',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('conflict_error_dialog')),
        findsOneWidget,
      );
      // The resolver itself is still mounted underneath — the user can
      // dismiss the error and retry CANCEL (or resolve normally) instead of
      // being left with a wedged rebase and no UI.
      expect(find.byKey(const ValueKey('conflict_cancel')), findsOneWidget);
      await controller.close();
    },
  );

  testWidgets(
    'reusing a row position across a batch transition (body conflict then '
    'a non-body conflict) does not crash on TAKE INCOMING',
    (tester) async {
      const batch1 = [
        FileConflict(
          path: 'r1.req.json',
          kind: ConflictKind.request,
          node: NodeMergeResult(
            merged: _node,
            conflicts: [
              FieldConflict(
                field: 'body',
                kind: FieldConflictKind.scalar,
                incoming: '{"a":1}',
                yours: '{"a":2}',
              ),
            ],
          ),
        ),
      ];
      const batch2 = [
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
      final controller = StreamController<ConflictState>();
      whenListen(
        conflictBloc,
        controller.stream,
        initialState: const ConflictState(
          status: ConflictStatus.ready,
          conflicts: batch1,
        ),
      );

      await openDialog(tester);
      controller.add(
        const ConflictState(
          status: ConflictStatus.ready,
          conflicts: batch2,
          batch: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('take_incoming_r1.req.json_url')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await controller.close();
    },
  );

  testWidgets(
    'a done status (non-abort) closes the dialog, shows the resolved '
    'snackbar, and dispatches ConflictsResolved — FIX C2: this must reload '
    'the tree, not just refresh branch status',
    (tester) async {
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
      expect(find.text('Conflicts resolved.'), findsOneWidget);
      verify(() => gitBloc.add(const ConflictsResolved(root))).called(1);
      verifyNever(() => gitBloc.add(const LoadBranchStatus(root)));
      await controller.close();
    },
  );

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

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockReviewBloc extends MockBloc<ReviewEvent, ReviewState>
    implements ReviewBloc {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

void main() {
  late _MockReviewBloc bloc;
  late _MockSettingsBloc settingsBloc;
  late _MockGitSyncBloc gitSyncBloc;

  const entry = ReviewEntry(
    path: 'a.req.json',
    nodeKind: NodeKind.request,
    changeType: ChangeType.modified,
    displayName: 'Get User',
    staged: false,
    diff: SemanticDiff([
      FieldChange(
        field: 'method',
        kind: ChangeKind.changed,
        before: 'GET',
        after: 'POST',
      ),
    ]),
  );

  setUp(() {
    bloc = _MockReviewBloc();
    settingsBloc = _MockSettingsBloc();
    gitSyncBloc = _MockGitSyncBloc();
    when(
      () => settingsBloc.state,
    ).thenReturn(const SettingsState(settings: SettingsEntity()));
    when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => gitSyncBloc.state).thenReturn(
      const GitSyncState(
        status: GitSyncStatus.ready,
        branch: BranchStatus(
          isRepo: true,
          current: 'main',
          branches: ['main'],
          hasRemote: true,
        ),
      ),
    );
    when(() => gitSyncBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget host(ReviewState state) {
    when(() => bloc.state).thenReturn(state);
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ReviewBloc>.value(value: bloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<GitSyncBloc>.value(value: gitSyncBloc),
        ],
        child: const Scaffold(body: ReviewChangesBody(root: '/ws')),
      ),
    );
  }

  testWidgets('lists changed nodes and shows the selected diff', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ReviewState(
          status: ReviewStatus.ready,
          entries: [entry],
          selectedPath: 'a.req.json',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Get User'), findsWidgets);
    expect(find.textContaining('method'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Commit disabled until a node is staged + message present', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ReviewState(
          status: ReviewStatus.ready,
          entries: [entry],
          selectedPath: 'a.req.json',
        ),
      ),
    );
    final commit = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('review_commit_button')),
    );
    expect(commit.onPressed, isNull); // nothing staged yet
  });

  testWidgets('the select-all header stages every entry', (tester) async {
    await tester.pumpWidget(
      host(
        const ReviewState(
          status: ReviewStatus.ready,
          entries: [entry],
          selectedPath: 'a.req.json',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SELECT ALL'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review_select_all')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const StageAll('/ws'))).called(1);
  });

  testWidgets('with everything staged the header clears the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ReviewState(
          status: ReviewStatus.ready,
          entries: [
            ReviewEntry(
              path: 'a.req.json',
              nodeKind: NodeKind.request,
              changeType: ChangeType.modified,
              displayName: 'Get User',
              staged: true,
              diff: SemanticDiff([]),
            ),
          ],
          selectedPath: 'a.req.json',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DESELECT ALL'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review_select_all')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const UnstageAll('/ws'))).called(1);
  });

  testWidgets('the entry path carries a tooltip with its full path', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ReviewState(
          status: ReviewStatus.ready,
          entries: [entry],
          selectedPath: 'a.req.json',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.text('a.req.json'),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, '/ws/a.req.json');
  });

  testWidgets('not a repo shows Initialize git', (tester) async {
    await tester.pumpWidget(
      host(const ReviewState(status: ReviewStatus.ready, repoExists: false)),
    );
    expect(find.textContaining('Initialize git'), findsOneWidget);
  });

  testWidgets('the PUSH button is present when the workspace is a repo', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const ReviewState(status: ReviewStatus.ready)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('review_push_button')), findsOneWidget);
  });

  // Pushed via a real route (unlike `host()`, which renders the body
  // directly as `home:`) so `Navigator.of(context).maybePop()` inside the
  // PUSH handler has something real to pop — mirrors how
  // `ReviewChangesDialog.show` actually opens this body.
  Widget hostAsRoute(ReviewState state) {
    when(() => bloc.state).thenReturn(state);
    // The providers wrap `MaterialApp` itself (not just `home:`), matching
    // main.dart's root MultiBlocProvider — a route pushed via `Navigator.push`
    // lands in the same Overlay as `home`, a *sibling* of it in the element
    // tree, not a descendant, so providers scoped only to `home:` would not
    // be reachable from the pushed route.
    return MultiBlocProvider(
      providers: [
        BlocProvider<ReviewBloc>.value(value: bloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        BlocProvider<GitSyncBloc>.value(value: gitSyncBloc),
      ],
      child: MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: ReviewChangesBody(root: '/ws')),
                  ),
                ),
                child: const Text('open review'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'pressing PUSH with a remote present dispatches PushChanges and pops',
    (tester) async {
      await tester.pumpWidget(
        hostAsRoute(const ReviewState(status: ReviewStatus.ready)),
      );
      await tester.tap(find.text('open review'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('review_push_button')));
      await tester.pumpAndSettle();

      verify(() => gitSyncBloc.add(const PushChanges('/ws'))).called(1);
      // The dialog route itself was popped.
      expect(find.byKey(const ValueKey('review_push_button')), findsNothing);
    },
  );

  testWidgets(
    'pressing PUSH with no remote prompts for a URL before pushing',
    (tester) async {
      when(() => gitSyncBloc.state).thenReturn(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
          ),
        ),
      );

      await tester.pumpWidget(
        host(const ReviewState(status: ReviewStatus.ready)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('review_push_button')));
      await tester.pumpAndSettle();

      expect(find.text('ADD REMOTE'), findsWidgets);
      expect(find.byKey(const ValueKey('name_prompt_field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('name_prompt_field')),
        'https://example.invalid/x/y.git',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'ADD REMOTE'));
      await tester.pumpAndSettle();

      verify(
        () => gitSyncBloc.add(
          const PushChanges(
            '/ws',
            addRemoteUrl: 'https://example.invalid/x/y.git',
          ),
        ),
      ).called(1);
    },
  );

  testWidgets('surfaces the error message after a failed commit', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ReviewState(
          status: ReviewStatus.error,
          entries: [entry],
          selectedPath: 'a.req.json',
          errorMessage: 'boom',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('boom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a commit failing with needsIdentity opens the identity prompt; SAVE '
    'dispatches UpdateGitIdentity then re-dispatches Commit',
    (tester) async {
      final controller = StreamController<ReviewState>();
      const readyState = ReviewState(
        status: ReviewStatus.ready,
        entries: [entry],
        selectedPath: 'a.req.json',
      );
      whenListen(bloc, controller.stream, initialState: readyState);

      await tester.pumpWidget(host(readyState));
      await tester.pumpAndSettle();

      // No prompt yet.
      expect(find.byKey(const ValueKey('git_identity_dialog')), findsNothing);

      controller.add(
        const ReviewState(
          status: ReviewStatus.needsIdentity,
          entries: [entry],
          selectedPath: 'a.req.json',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('git_identity_dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('git_identity_name_field')),
        'Ada Lovelace',
      );
      await tester.enterText(
        find.byKey(const ValueKey('git_identity_email_field')),
        'ada@example.com',
      );
      // SAVE is gated on both fields being non-empty (FIX 1) — pump so the
      // rebuild from the second field's onChanged lands before the tap.
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('git_identity_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('git_identity_dialog')), findsNothing);
      verify(
        () => settingsBloc.add(
          const UpdateGitIdentity(
            name: 'Ada Lovelace',
            email: 'ada@example.com',
          ),
        ),
      ).called(1);
      verify(
        () => bloc.add(
          const Commit(
            '/ws',
            '',
            authorName: 'Ada Lovelace',
            authorEmail: 'ada@example.com',
          ),
        ),
      ).called(1);

      await controller.close();
    },
  );

  testWidgets(
    'the identity prompt SAVE button is disabled while the email (or name) '
    'field is blank',
    (tester) async {
      final controller = StreamController<ReviewState>();
      const readyState = ReviewState(
        status: ReviewStatus.ready,
        entries: [entry],
        selectedPath: 'a.req.json',
      );
      whenListen(bloc, controller.stream, initialState: readyState);

      await tester.pumpWidget(host(readyState));
      await tester.pumpAndSettle();

      controller.add(
        const ReviewState(
          status: ReviewStatus.needsIdentity,
          entries: [entry],
          selectedPath: 'a.req.json',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('git_identity_dialog')), findsOneWidget);

      FilledButton saveButton() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('git_identity_save')),
      );

      // Both fields blank → disabled.
      expect(saveButton().onPressed, isNull);

      // Name only → still disabled (email blank).
      await tester.enterText(
        find.byKey(const ValueKey('git_identity_name_field')),
        'Ada Lovelace',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNull);

      // Both filled → enabled.
      await tester.enterText(
        find.byKey(const ValueKey('git_identity_email_field')),
        'ada@example.com',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);

      // Email cleared back to blank (whitespace-only) → disabled again.
      await tester.enterText(
        find.byKey(const ValueKey('git_identity_email_field')),
        '   ',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNull);

      await controller.close();
    },
  );
}

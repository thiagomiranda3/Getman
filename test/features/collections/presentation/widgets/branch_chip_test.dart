import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_event.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_state.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:getman/features/collections/presentation/widgets/branch_chip.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

class _MockWorkspaceDataSource extends Mock
    implements WorkspaceCollectionsDataSource {}

class _MockPullRequestsBloc
    extends MockBloc<PullRequestsEvent, PullRequestsState>
    implements PullRequestsBloc {}

class _MockConflictBloc extends MockBloc<ConflictEvent, ConflictState>
    implements ConflictBloc {}

class _MockReviewBloc extends MockBloc<ReviewEvent, ReviewState>
    implements ReviewBloc {}

void main() {
  const root = '/ws';
  late _MockGitSyncBloc bloc;
  late _MockSettingsBloc settings;
  late _MockPullRequestsBloc prBloc;
  late _MockConflictBloc conflictBloc;
  late _MockReviewBloc reviewBloc;

  setUpAll(() {
    // Needed for `captureAny()` on `bloc.add(...)` in the PULL-no-remote
    // test below — mocktail requires a registered fallback for any type
    // used with `any`/`captureAny`.
    registerFallbackValue(const LoadBranchStatus(root));
  });

  setUp(() {
    bloc = _MockGitSyncBloc();
    settings = _MockSettingsBloc();
    when(() => settings.state).thenReturn(
      const SettingsState(settings: SettingsEntity(workspacePath: root)),
    );
    when(() => settings.stream).thenAnswer((_) => const Stream.empty());
    prBloc = _MockPullRequestsBloc();
    when(() => prBloc.state).thenReturn(
      const PullRequestsState(status: PrStatus.ready),
    );
    conflictBloc = _MockConflictBloc();
    when(() => conflictBloc.state).thenReturn(
      const ConflictState(status: ConflictStatus.ready),
    );
    reviewBloc = _MockReviewBloc();
    when(() => reviewBloc.state).thenReturn(
      const ReviewState(status: ReviewStatus.ready),
    );
  });

  Widget host(GitSyncState state) {
    when(() => bloc.state).thenReturn(state);
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: RepositoryProvider<WorkspaceSyncService>(
          create: (_) => WorkspaceSyncService(_MockWorkspaceDataSource()),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<GitSyncBloc>.value(value: bloc),
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<PullRequestsBloc>.value(value: prBloc),
              BlocProvider<ConflictBloc>.value(value: conflictBloc),
              BlocProvider<ReviewBloc>.value(value: reviewBloc),
            ],
            child: const BranchChip(),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the branch name and ahead/behind counts', (tester) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
            ahead: 2,
            behind: 3,
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('main'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is hidden when the workspace is not a git repo', (tester) async {
    await tester.pumpWidget(
      host(const GitSyncState(status: GitSyncStatus.ready)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('branch_chip')), findsNothing);
  });

  testWidgets('the menu switches branch on tap', (tester) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main', 'feat/x'],
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feat/x').last);
    await tester.pumpAndSettle();

    verify(() => bloc.add(const SwitchBranch(root, 'feat/x'))).called(1);
  });

  testWidgets('Pull dispatches PullChanges', (tester) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('branch_menu_pull')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const PullChanges(root))).called(1);
  });

  testWidgets('PUSH dispatches PushChanges when a remote exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('branch_menu_push')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const PushChanges(root))).called(1);
  });

  testWidgets(
    'PUSH with no remote opens the ADD REMOTE prompt; confirming dispatches '
    'PushChanges with addRemoteUrl',
    (tester) async {
      await tester.pumpWidget(
        host(
          const GitSyncState(
            status: GitSyncStatus.ready,
            branch: BranchStatus(
              isRepo: true,
              current: 'main',
              branches: ['main'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('branch_menu_push')));
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
        () => bloc.add(
          const PushChanges(
            root,
            addRemoteUrl: 'https://example.invalid/x/y.git',
          ),
        ),
      ).called(1);
    },
  );

  testWidgets(
    'PULL with no remote opens the ADD REMOTE prompt; confirming dispatches '
    'PullChanges with addRemoteUrl',
    (tester) async {
      await tester.pumpWidget(
        host(
          const GitSyncState(
            status: GitSyncStatus.ready,
            branch: BranchStatus(
              isRepo: true,
              current: 'main',
              branches: ['main'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('branch_menu_pull')));
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

      final captured = verify(
        () => bloc.add(captureAny(that: isA<PullChanges>())),
      ).captured;
      expect(captured, hasLength(1));
      final event = captured.single as PullChanges;
      expect(event.root, root);
      expect(event.addRemoteUrl, 'https://example.invalid/x/y.git');
      // Identity fields are threaded through from SettingsBloc, exactly as
      // the hasRemote-true PULL path does.
      expect(event.authorName, settings.state.settings.gitUserName);
      expect(event.authorEmail, settings.state.settings.gitUserEmail);
    },
  );

  testWidgets('FETCH dispatches FetchRemote', (tester) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('branch_menu_fetch')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const FetchRemote(root))).called(1);
  });

  testWidgets(
    'FETCH with no remote opens the ADD REMOTE prompt; confirming dispatches '
    'FetchRemote with addRemoteUrl',
    (tester) async {
      await tester.pumpWidget(
        host(
          const GitSyncState(
            status: GitSyncStatus.ready,
            branch: BranchStatus(
              isRepo: true,
              current: 'main',
              branches: ['main'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('branch_menu_fetch')));
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
        () => bloc.add(
          const FetchRemote(
            root,
            addRemoteUrl: 'https://example.invalid/x/y.git',
          ),
        ),
      ).called(1);
    },
  );

  testWidgets('a dirty-switch error shows the commit/stash prompt', (
    tester,
  ) async {
    whenListen(
      bloc,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(
          status: GitSyncStatus.error,
          errorMessage: 'You have uncommitted changes',
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main', 'feat/x'],
          ),
        ),
      ]),
      initialState: const GitSyncState(
        status: GitSyncStatus.ready,
        branch: BranchStatus(
          isRepo: true,
          current: 'main',
          branches: ['main', 'feat/x'],
        ),
      ),
    );

    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main', 'feat/x'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REVIEW CHANGES…'), findsOneWidget);
    expect(find.text('STASH CHANGES'), findsOneWidget);
  });

  const repoState = GitSyncState(
    status: GitSyncStatus.ready,
    branch: BranchStatus(
      isRepo: true,
      current: 'main',
      branches: ['main'],
      hasRemote: true,
    ),
  );

  testWidgets('NEW BRANCH prompts for a name and dispatches CreateBranch', (
    tester,
  ) async {
    await tester.pumpWidget(host(repoState));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NEW BRANCH…'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('name_prompt_field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('name_prompt_field')),
      'feat/shiny',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'CREATE'));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const CreateBranch(root, 'feat/shiny'))).called(1);
  });

  testWidgets('the STASHES item carries the count and opens the stash list', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
            hasRemote: true,
            stashes: [
              StashInfo(index: 0, message: 'WIP on main'),
              StashInfo(index: 1, message: 'Getman WIP'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    expect(find.text('STASHES (2)'), findsOneWidget);

    await tester.tap(find.text('STASHES (2)'));
    await tester.pumpAndSettle();

    expect(find.text('STASHES'), findsOneWidget);
    expect(find.text('WIP on main'), findsOneWidget);
    expect(find.text('Getman WIP'), findsOneWidget);
  });

  testWidgets('PULL REQUESTS… opens the PR dialog and loads the list', (
    tester,
  ) async {
    await tester.pumpWidget(host(repoState));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PULL REQUESTS…'));
    await tester.pumpAndSettle();

    expect(find.text('PULL REQUESTS'), findsOneWidget);
    verify(() => prBloc.add(const LoadPullRequests(root))).called(1);
  });

  testWidgets('a generic git error opens the GIT ERROR dialog', (
    tester,
  ) async {
    whenListen(
      bloc,
      Stream<GitSyncState>.fromIterable([
        repoState.copyWith(
          status: GitSyncStatus.error,
          errorMessage: 'fatal: remote imploded',
        ),
      ]),
      initialState: repoState,
    );

    await tester.pumpWidget(host(repoState));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('branch_error_dialog')), findsOneWidget);
    expect(find.text('fatal: remote imploded'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('branch_error_dialog')), findsNothing);
  });

  testWidgets('the dirty prompt STASH CHANGES dispatches StashChanges', (
    tester,
  ) async {
    whenListen(
      bloc,
      Stream<GitSyncState>.fromIterable([
        repoState.copyWith(
          status: GitSyncStatus.error,
          errorMessage: 'You have uncommitted changes',
        ),
      ]),
      initialState: repoState,
    );

    await tester.pumpWidget(host(repoState));
    await tester.pumpAndSettle();

    await tester.tap(find.text('STASH CHANGES'));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const StashChanges(root, 'Getman WIP'))).called(1);
    expect(find.text('UNCOMMITTED CHANGES'), findsNothing); // prompt closed
  });

  testWidgets('the dirty prompt REVIEW CHANGES… opens the review dialog', (
    tester,
  ) async {
    whenListen(
      bloc,
      Stream<GitSyncState>.fromIterable([
        repoState.copyWith(
          status: GitSyncStatus.error,
          errorMessage: 'You have uncommitted changes',
        ),
      ]),
      initialState: repoState,
    );

    await tester.pumpWidget(host(repoState));
    await tester.pumpAndSettle();

    await tester.tap(find.text('REVIEW CHANGES…'));
    await tester.pumpAndSettle();

    verify(() => reviewBloc.add(const LoadReview(root))).called(1);
    expect(find.text('No changes to review.'), findsOneWidget);
  });

  testWidgets('a conflictToken bump opens the conflict resolver exactly once', (
    tester,
  ) async {
    whenListen(
      bloc,
      Stream<GitSyncState>.fromIterable([repoState.copyWith(conflictToken: 1)]),
      initialState: repoState,
    );

    await tester.pumpWidget(host(repoState));
    await tester.pumpAndSettle();

    expect(find.text('Resolving conflicts — commit 1'), findsOneWidget);
  });

  testWidgets('auto-fetches silently every kAutoFetchInterval', (
    tester,
  ) async {
    await tester.pumpWidget(host(repoState));
    await tester.pumpAndSettle();

    // The post-frame boot already fired one silent fetch.
    verify(() => bloc.add(const FetchRemote(root, silent: true))).called(1);

    await tester.pump(kAutoFetchInterval);
    verify(() => bloc.add(const FetchRemote(root, silent: true))).called(1);

    await tester.pump(kAutoFetchInterval);
    verify(() => bloc.add(const FetchRemote(root, silent: true))).called(1);
  });
}

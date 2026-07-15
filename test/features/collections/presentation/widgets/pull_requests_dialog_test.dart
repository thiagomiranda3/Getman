import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';
import 'package:getman/features/collections/presentation/widgets/pull_requests_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _MockPrBloc extends MockBloc<PullRequestsEvent, PullRequestsState>
    implements PullRequestsBloc {}

class _MockGitBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

class _FakePrEvent extends Fake implements PullRequestsEvent {}

const _pr = PullRequestEntity(
  number: 77,
  title: 'feat: y',
  state: PrState.open,
  url: 'https://github.com/o/r/pull/77',
  isDraft: false,
  checks: PrChecks.passing,
);

void main() {
  const root = '/ws';

  setUpAll(() => registerFallbackValue(_FakePrEvent()));

  _MockGitBloc defaultGit() {
    final git = _MockGitBloc();
    when(() => git.state).thenReturn(const GitSyncState());
    return git;
  }

  Widget host(_MockPrBloc prBloc, {_MockGitBloc? gitBloc}) {
    // Use the caller's pre-stubbed git bloc as-is (stubbing here would clobber
    // the branches a test set up); synthesize a default only when none given.
    final git = gitBloc ?? defaultGit();
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<PullRequestsBloc>.value(value: prBloc),
            BlocProvider<GitSyncBloc>.value(value: git),
          ],
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => PullRequestsDialog.show(context, root: root),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('notInstalled shows the install prompt', (tester) async {
    final bloc = _MockPrBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
        availability: GhAvailability.notInstalled,
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('gh'), findsWidgets);
    expect(find.text('INSTALL GH'), findsOneWidget);
  });

  testWidgets('notAuthenticated shows the gh auth hint', (tester) async {
    final bloc = _MockPrBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
        availability: GhAvailability.notAuthenticated,
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('gh auth login'), findsOneWidget);
  });

  testWidgets('a ready list renders a PR row and the create button', (
    tester,
  ) async {
    final bloc = _MockPrBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
        prs: [
          PullRequestEntity(
            number: 42,
            title: 'feat: thing',
            state: PrState.open,
            url: 'https://github.com/o/r/pull/42',
            isDraft: false,
            checks: PrChecks.passing,
          ),
        ],
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('42'), findsWidgets);
    expect(find.text('feat: thing'), findsOneWidget);
    expect(find.text('CREATE PULL REQUEST…'), findsOneWidget);
  });

  testWidgets('empty ready list shows the empty message', (tester) async {
    final bloc = _MockPrBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('No open pull requests.'), findsOneWidget);
  });

  testWidgets('opening the dialog dispatches LoadPullRequests', (tester) async {
    final bloc = _MockPrBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const LoadPullRequests(root))).called(1);
  });

  testWidgets('the create form dispatches CreatePullRequest', (tester) async {
    final bloc = _MockPrBloc();
    final git = _MockGitBloc();
    when(() => git.state).thenReturn(
      const GitSyncState(
        branch: BranchStatus(
          isRepo: true,
          current: 'feat/x',
          branches: ['feat/x', 'main'],
        ),
      ),
    );
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
      ),
    );
    await tester.pumpWidget(host(bloc, gitBloc: git));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CREATE PULL REQUEST…'));
    await tester.pumpAndSettle();

    // Base is prefilled from the known branches ('main'); enter a title so the
    // submit enables.
    await tester.enterText(
      find.byKey(const ValueKey('pr_form_title')),
      'my pr',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pr_form_submit')));
    await tester.pumpAndSettle();

    verify(
      () => bloc.add(
        const CreatePullRequest(
          root,
          base: 'main',
          title: 'my pr',
          body: '',
          draft: false,
        ),
      ),
    ).called(1);
  });

  testWidgets('the draft toggle sends draft:true with the body', (
    tester,
  ) async {
    final bloc = _MockPrBloc();
    final git = _MockGitBloc();
    when(() => git.state).thenReturn(
      const GitSyncState(
        branch: BranchStatus(isRepo: true, current: 'x', branches: ['main']),
      ),
    );
    when(() => bloc.state).thenReturn(
      const PullRequestsState(status: PrStatus.ready),
    );
    await tester.pumpWidget(host(bloc, gitBloc: git));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE PULL REQUEST…'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('pr_form_title')), 't');
    await tester.enterText(find.byKey(const ValueKey('pr_form_body')), 'desc');
    await tester.tap(find.byKey(const ValueKey('pr_form_draft')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pr_form_submit')));
    await tester.pumpAndSettle();

    verify(
      () => bloc.add(
        const CreatePullRequest(
          root,
          base: 'main',
          title: 't',
          body: 'desc',
          draft: true,
        ),
      ),
    ).called(1);
  });

  testWidgets('a created PR nudges the chip once — not again on refresh', (
    tester,
  ) async {
    final bloc = _MockPrBloc();
    final git = _MockGitBloc();
    when(() => git.state).thenReturn(const GitSyncState());
    // Emit into a controller AFTER the dialog subscribes, so no state is lost.
    final controller = StreamController<PullRequestsState>();
    whenListen(
      bloc,
      controller.stream,
      initialState: const PullRequestsState(status: PrStatus.ready),
    );
    await tester.pumpWidget(host(bloc, gitBloc: git));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // First: the create resolves (lastCreated set). Then: a plain refresh with
    // the SAME lastCreated (list now carries the PR). The nudge must fire once.
    controller.add(
      const PullRequestsState(
        status: PrStatus.ready,
        lastCreated: PullRequestRef(number: 77, url: 'u/pull/77'),
      ),
    );
    await tester.pump();
    controller.add(
      const PullRequestsState(
        status: PrStatus.ready,
        prs: [_pr],
        lastCreated: PullRequestRef(number: 77, url: 'u/pull/77'),
      ),
    );
    await tester.pump();

    verify(() => git.add(const LoadBranchStatus(root))).called(1);
    await controller.close();
  });

  testWidgets('an error state shows the GIT ERROR dialog', (tester) async {
    final bloc = _MockPrBloc();
    final controller = StreamController<PullRequestsState>();
    whenListen(
      bloc,
      controller.stream,
      initialState: const PullRequestsState(status: PrStatus.ready),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    controller.add(
      const PullRequestsState(status: PrStatus.error, errorMessage: 'boom'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pr_error_dialog')), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    await controller.close();
  });

  testWidgets('a busy state disables the actions and shows a spinner', (
    tester,
  ) async {
    final bloc = _MockPrBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(status: PrStatus.creating),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    // A spinner animates forever — pump past the dialog-open transition only,
    // never pumpAndSettle (it would time out on the CircularProgressIndicator).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final refresh = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('pr_refresh')),
    );
    final create = tester.widget<FilledButton>(
      find.byKey(const ValueKey('pr_create')),
    );
    expect(refresh.onPressed, isNull);
    expect(create.onPressed, isNull);
  });
}

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/stash_list_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

void main() {
  const root = '/ws';

  Widget host(GitSyncState state, _MockGitSyncBloc bloc) {
    when(() => bloc.state).thenReturn(state);
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: BlocProvider<GitSyncBloc>.value(
        value: bloc,
        child: const Scaffold(body: StashListBody(root: root)),
      ),
    );
  }

  const withStashes = GitSyncState(
    status: GitSyncStatus.ready,
    branch: BranchStatus(
      isRepo: true,
      current: 'main',
      stashes: [StashInfo(index: 0, message: 'WIP on main: getman')],
    ),
  );

  testWidgets('lists stashes', (tester) async {
    final bloc = _MockGitSyncBloc();
    await tester.pumpWidget(host(withStashes, bloc));
    await tester.pumpAndSettle();

    expect(find.textContaining('WIP on main'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('POP dispatches PopStash', (tester) async {
    final bloc = _MockGitSyncBloc();
    await tester.pumpWidget(host(withStashes, bloc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stash_pop_0')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const PopStash(root, 0))).called(1);
  });

  testWidgets('DROP confirms before dispatching DropStash', (tester) async {
    final bloc = _MockGitSyncBloc();
    await tester.pumpWidget(host(withStashes, bloc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stash_drop_0')));
    await tester.pumpAndSettle();

    // The confirm dialog is up; nothing dispatched until the user confirms.
    expect(find.text('DROP STASH'), findsOneWidget);
    verifyNever(() => bloc.add(const DropStash(root, 0)));

    // Confirm button carries the same 'DROP' label; it is the later one in
    // the tree (the dialog overlay sits above the row button).
    await tester.tap(find.widgetWithText(TextButton, 'DROP').last);
    await tester.pumpAndSettle();

    verify(() => bloc.add(const DropStash(root, 0))).called(1);
  });

  testWidgets('actions are disabled while an op is in flight', (tester) async {
    final bloc = _MockGitSyncBloc();
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.busy,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            stashes: [StashInfo(index: 0, message: 'WIP on main: getman')],
          ),
        ),
        bloc,
      ),
    );
    await tester.pumpAndSettle();

    final pop = tester.widget<TextButton>(
      find.byKey(const ValueKey('stash_pop_0')),
    );
    final drop = tester.widget<TextButton>(
      find.byKey(const ValueKey('stash_drop_0')),
    );
    expect(pop.onPressed, isNull);
    expect(drop.onPressed, isNull);

    // Tapping a disabled button dispatches nothing.
    await tester.tap(find.byKey(const ValueKey('stash_pop_0')));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.add(const PopStash(root, 0)));
  });

  testWidgets('empty state tells the user there is nothing stashed', (
    tester,
  ) async {
    final bloc = _MockGitSyncBloc();
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(isRepo: true, current: 'main'),
        ),
        bloc,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No stashes.'), findsOneWidget);
  });
}

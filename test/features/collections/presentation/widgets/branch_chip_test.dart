import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
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

void main() {
  const root = '/ws';
  late _MockGitSyncBloc bloc;
  late _MockSettingsBloc settings;

  setUp(() {
    bloc = _MockGitSyncBloc();
    settings = _MockSettingsBloc();
    when(() => settings.state).thenReturn(
      const SettingsState(settings: SettingsEntity(workspacePath: root)),
    );
    when(() => settings.stream).thenAnswer((_) => const Stream.empty());
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
}

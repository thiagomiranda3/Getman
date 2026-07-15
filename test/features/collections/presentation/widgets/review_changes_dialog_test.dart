import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
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

void main() {
  late _MockReviewBloc bloc;
  late _MockSettingsBloc settingsBloc;

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
    when(
      () => settingsBloc.state,
    ).thenReturn(const SettingsState(settings: SettingsEntity()));
    when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget host(ReviewState state) {
    when(() => bloc.state).thenReturn(state);
    return MaterialApp(
      theme: resolveTheme('classic')(Brightness.light),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ReviewBloc>.value(value: bloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
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
}

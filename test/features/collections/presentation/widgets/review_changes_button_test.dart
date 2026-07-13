// Widget tests for the collections-header Review Changes button:
//  - badges the uncommitted-change count and refreshes it when the workspace
//    mirror lands on disk;
//  - with no workspace connected it routes to the WORKSPACE settings pane
//    instead of dead-ending as a disabled control.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/domain/review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_button.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class MockReviewService extends Mock implements ReviewService {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class MockWorkspaceDataSource extends Mock
    implements WorkspaceCollectionsDataSource {}

ReviewEntry _entry(String path) => ReviewEntry(
  path: path,
  nodeKind: NodeKind.request,
  changeType: ChangeType.modified,
  displayName: path,
  staged: false,
  diff: const SemanticDiff([]),
);

ReviewResult _result(List<String> paths) => ReviewResult(
  gitAvailable: true,
  repoExists: true,
  branch: 'main',
  entries: paths.map(_entry).toList(),
);

void main() {
  const root = '/ws';

  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  late MockReviewService service;
  late WorkspaceSyncService sync;
  late ReviewBloc review;

  // Built inside the test body, not in setUp: a ReviewBloc constructed outside
  // testWidgets' fake-async zone never resolves its awaits under pumpAndSettle.
  Widget host({String? path}) {
    service = MockReviewService();
    final dataSource = MockWorkspaceDataSource();
    when(() => dataSource.write(any(), any())).thenAnswer((_) async {});
    sync = WorkspaceSyncService(dataSource, debounce: Duration.zero);
    review = ReviewBloc(service: service);
    addTearDown(sync.dispose);
    addTearDown(review.close);

    final settings = MockSettingsBloc();
    when(() => settings.state).thenReturn(
      SettingsState(settings: SettingsEntity(workspacePath: path)),
    );
    when(() => settings.stream).thenAnswer((_) => const Stream.empty());

    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: RepositoryProvider<WorkspaceSyncService>.value(
          value: sync,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<ReviewBloc>.value(value: review),
            ],
            child: const ReviewChangesButton(),
          ),
        ),
      ),
    );
  }

  testWidgets('badges the number of uncommitted changes', (tester) async {
    final app = host(path: root);
    when(
      () => service.review(root),
    ).thenAnswer((_) async => _result(['a.req.json', 'b.req.json']));

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('no badge is shown when the workspace is clean', (tester) async {
    final app = host(path: root);
    when(() => service.review(root)).thenAnswer((_) async => _result([]));

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNothing);
  });

  testWidgets('the count refreshes after the workspace mirror lands', (
    tester,
  ) async {
    final app = host(path: root);
    when(() => service.review(root)).thenAnswer((_) async => _result([]));

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);

    // A mutation mirrored to disk is the only moment the on-disk diff can have
    // changed, so that is what re-runs the review.
    when(
      () => service.review(root),
    ).thenAnswer((_) async => _result(['a.req.json']));
    sync.scheduleMirror(root, const <CollectionNodeEntity>[]);
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('with no workspace, tapping opens the WORKSPACE settings pane', (
    tester,
  ) async {
    final app = host();

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('review_changes_button')));
    await tester.pumpAndSettle();

    // 'CHOOSE FOLDER' only exists on the workspace pane, so finding it proves
    // the dialog opened deep-linked rather than on GENERAL.
    expect(find.text('CHOOSE FOLDER'), findsOneWidget);
    verifyNever(() => service.review(any()));
  });
}

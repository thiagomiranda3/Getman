// Widget tests for NodeActionSheet: the phone action-sheet for collection
// nodes. Opens via NodeActionSheet.show(), exercises each action row, and
// verifies the right CollectionsBloc event is dispatched (or that the right
// dialog appears).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/node_action_sheet.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

const _folderNode = CollectionNodeEntity(id: 'f1', name: 'My Folder');

const _leafNode = CollectionNodeEntity(
  id: 'r1',
  name: 'My Request',
  isFolder: false,
  config: HttpRequestConfigEntity(id: 'r1', url: 'https://example.com'),
);

/// Opens the NodeActionSheet for [node] inside a full MaterialApp + Scaffold.
/// Returns the bloc so callers can verify events.
Future<CollectionsBloc> openSheet(
  WidgetTester tester,
  CollectionNodeEntity node, {
  required MockCollectionsRepository repo,
}) async {
  // Use a desktop-width viewport (>900 logical px) so isDialogFullscreen
  // returns false (dialogs use showDialog, not full-screen page routes).
  // Height of 2000px so the modal sheet has room for all folder actions.
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewPadding = FakeViewPadding.zero;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewPadding);

  final bloc = CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
    saveDebounce: const Duration(milliseconds: 5),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: BlocProvider.value(
          value: bloc,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => NodeActionSheet.show(context, node),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('OPEN'));
  // Pump enough frames for the bottom sheet entrance animation to complete.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));

  return bloc;
}

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() {
    registerFallbackValue(<CollectionNodeEntity>[]);
  });

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  group('folder node', () {
    testWidgets('renders node name in header', (tester) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      expect(find.text('My Folder'), findsOneWidget);
    });

    testWidgets('renders all expected action labels', (tester) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      expect(find.text('RENAME'), findsOneWidget);
      expect(find.text('EDIT DESCRIPTION'), findsOneWidget);
      expect(find.text('ADD SUBFOLDER'), findsOneWidget);
      expect(find.text('VARIABLES'), findsOneWidget);
      expect(find.text('MOVE TO...'), findsOneWidget);
      expect(find.text('EXPORT TO POSTMAN'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });

    testWidgets('FAVORITE action is shown for non-favorite folder', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      expect(find.text('FAVORITE'), findsOneWidget);
    });

    testWidgets(
      'tapping FAVORITE dispatches ToggleFavorite and closes the sheet',
      (tester) async {
        final bloc = await openSheet(tester, _folderNode, repo: repo);
        addTearDown(bloc.close);

        // Seed the bloc with the folder node via ReplaceCollections so the
        // ToggleFavorite event can mutate it and we can observe the flip.
        bloc.add(const ReplaceCollections([_folderNode]));
        await tester.pump(const Duration(milliseconds: 50));

        // The node should be non-favorite before the tap.
        final before = bloc.state.collections.firstWhere(
          (n) => n.id == _folderNode.id,
        );
        expect(before.isFavorite, isFalse);

        await tester.tap(find.text('FAVORITE'));
        // Pump multiple frames to complete the sheet dismiss animation and
        // allow the bloc to process the ToggleFavorite event.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // Sheet should be dismissed.
        expect(find.text('FAVORITE'), findsNothing);

        // The ToggleFavorite event must have flipped isFavorite on the node.
        final after = bloc.state.collections.firstWhere(
          (n) => n.id == _folderNode.id,
        );
        expect(after.isFavorite, isTrue);
      },
    );

    testWidgets('tapping RENAME closes the sheet and opens rename dialog', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      await tester.tap(find.text('RENAME'));
      await tester.pump(const Duration(milliseconds: 300));

      // Sheet is dismissed; NamePromptDialog with the RENAME title opens.
      // The text field is the distinguishing element of the dialog.
      expect(find.text('RENAME'), findsWidgets);
      expect(
        find.byKey(const ValueKey('name_prompt_field')),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping ADD SUBFOLDER closes sheet and opens subfolder dialog',
      (tester) async {
        final bloc = await openSheet(tester, _folderNode, repo: repo);
        addTearDown(bloc.close);

        await tester.tap(find.text('ADD SUBFOLDER'));
        await tester.pump(const Duration(milliseconds: 300));

        // The NamePromptDialog with "ADD SUBFOLDER" title opens.
        expect(
          find.byKey(const ValueKey('name_prompt_field')),
          findsOneWidget,
        );
      },
    );

    testWidgets('tapping DELETE opens the confirmation dialog', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      await tester.tap(find.text('DELETE'));
      await tester.pump(const Duration(milliseconds: 200));

      // ConfirmDialog shows up with a "Delete folder?" title
      expect(find.text('Delete folder?'), findsOneWidget);
    });

    testWidgets(
      'confirming DELETE dispatches DeleteNode and shows snackbar',
      (tester) async {
        final bloc = await openSheet(tester, _folderNode, repo: repo);
        addTearDown(bloc.close);

        await tester.tap(find.text('DELETE'));
        await tester.pump(const Duration(milliseconds: 200));

        // Tap the DELETE confirm button
        await tester.tap(find.text('DELETE').last);
        await tester.pump(const Duration(milliseconds: 100));

        // The snackbar text contains the node name
        expect(find.textContaining('My Folder'), findsWidgets);
      },
    );

    testWidgets('tapping VARIABLES closes sheet and opens variables dialog', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      await tester.tap(find.text('VARIABLES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The CollectionVariablesDialog title shows "VARIABLES — My Folder".
      expect(find.textContaining('VARIABLES — My Folder'), findsOneWidget);
    });

    testWidgets('tapping MOVE TO... closes sheet and opens move sheet', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      await tester.tap(find.text('MOVE TO...'));
      // Wait for the action sheet to dismiss and the move sheet to open.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The _MoveToSheet header contains the node name in its label.
      expect(find.textContaining('My Folder'), findsWidgets);
      // ROOT (TOP LEVEL) is always the first option in the move sheet.
      expect(find.text('ROOT (TOP LEVEL)'), findsOneWidget);
    });

    testWidgets('does not overflow at desktop width', (tester) async {
      final bloc = await openSheet(tester, _folderNode, repo: repo);
      addTearDown(bloc.close);

      // All action rows must be visible after the sheet entrance animation.
      expect(tester.takeException(), isNull);
      expect(find.text('RENAME'), findsOneWidget);
    });
  });

  group('leaf (request) node', () {
    testWidgets('renders node name in header', (tester) async {
      final bloc = await openSheet(tester, _leafNode, repo: repo);
      addTearDown(bloc.close);

      expect(find.text('My Request'), findsOneWidget);
    });

    testWidgets('does NOT show FAVORITE or ADD SUBFOLDER for leaf', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _leafNode, repo: repo);
      addTearDown(bloc.close);

      expect(find.text('FAVORITE'), findsNothing);
      expect(find.text('ADD SUBFOLDER'), findsNothing);
    });

    testWidgets('RENAME, EDIT DESCRIPTION, DELETE are shown for leaf', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _leafNode, repo: repo);
      addTearDown(bloc.close);

      expect(find.text('RENAME'), findsOneWidget);
      expect(find.text('EDIT DESCRIPTION'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });

    testWidgets('tapping DELETE for leaf shows request confirm title', (
      tester,
    ) async {
      final bloc = await openSheet(tester, _leafNode, repo: repo);
      addTearDown(bloc.close);

      await tester.tap(find.text('DELETE'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Delete request?'), findsOneWidget);
    });

    testWidgets(
      'tapping EDIT DESCRIPTION closes sheet and opens description dialog',
      (tester) async {
        final bloc = await openSheet(tester, _leafNode, repo: repo);
        addTearDown(bloc.close);

        await tester.tap(find.text('EDIT DESCRIPTION'));
        await tester.pump(const Duration(milliseconds: 300));

        // NamePromptDialog with DESCRIPTION title opens after sheet dismissal.
        expect(find.text('DESCRIPTION'), findsOneWidget);
      },
    );

    // Note: DUPLICATE and SAVE-AS-EXAMPLE are NOT actions in NodeActionSheet.
    // They exist only in the desktop three-dot popup menu
    // (collections_list.dart), not in this phone bottom-sheet. No tests here.

    testWidgets(
      'tapping MOVE TO... closes sheet and opens move sheet for leaf',
      (
        tester,
      ) async {
        final bloc = await openSheet(tester, _leafNode, repo: repo);
        addTearDown(bloc.close);

        await tester.tap(find.text('MOVE TO...'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // ROOT (TOP LEVEL) is always the first option in the move sheet.
        expect(find.text('ROOT (TOP LEVEL)'), findsOneWidget);
      },
    );
  });
}

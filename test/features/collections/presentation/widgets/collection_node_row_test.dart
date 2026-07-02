import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_row.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

void main() {
  late MockCollectionsRepository repo;

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc buildBloc() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
  );

  const requestNode = CollectionNodeEntity(
    id: 'req-1',
    name: 'GetUser',
    isFolder: false,
    config: HttpRequestConfigEntity(id: 'req-1'),
  );

  const favoriteFolder = CollectionNodeEntity(
    id: 'fav-1',
    name: 'Favorites',
    isFavorite: true,
  );

  Widget host({required bool isSelected}) {
    final bloc = buildBloc();
    return MaterialApp(
      theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
      home: Scaffold(
        body: BlocProvider<CollectionsBloc>.value(
          value: bloc,
          child: CollectionNodeRow(
            node: requestNode,
            isExpanded: false,
            depth: 0,
            onToggle: () {},
            rowWidth: 300,
            rowHeight: 44,
            isSelected: isSelected,
          ),
        ),
      ),
    );
  }

  Widget favoriteHost(ThemeData theme) {
    final bloc = buildBloc();
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: BlocProvider<CollectionsBloc>.value(
          value: bloc,
          child: const CollectionNodeRow(
            node: favoriteFolder,
            isExpanded: false,
            depth: 0,
            onToggle: _noop,
            rowWidth: 300,
            rowHeight: 44,
          ),
        ),
      ),
    );
  }

  // Finds the AnimatedContainer whose BoxDecoration has a non-null border —
  // the selected accent bar. Returns null if none.
  BoxDecoration? selectedDecoration(WidgetTester tester) {
    final containers = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration! as BoxDecoration)
        .where((d) => d.border != null);
    return containers.isEmpty ? null : containers.first;
  }

  testWidgets('request row paints a left accent border when selected', (
    tester,
  ) async {
    await tester.pumpWidget(host(isSelected: true));
    await tester.pumpAndSettle();

    final deco = selectedDecoration(tester);
    expect(deco, isNotNull, reason: 'selected row should have a border');
    final border = deco!.border! as Border;
    expect(border.left.width, greaterThan(0));
    // Background fill is present (non-transparent).
    expect(deco.color, isNotNull);
    expect(deco.color, isNot(Colors.transparent));
  });

  testWidgets('request row has no accent border when not selected', (
    tester,
  ) async {
    await tester.pumpWidget(host(isSelected: false));
    await tester.pumpAndSettle();

    expect(selectedDecoration(tester), isNull);
  });

  // Regression: the favorite-folder star used `theme.primaryColor`, which AURIS
  // leaves unset so Material defaults it to `colorScheme.surface` in dark mode
  // (near-black) — the star vanished into the background. It must use the brand
  // accent (`colorScheme.primary`), which is visible in both brightnesses.
  testWidgets('AURIS dark: favorite star is the visible brand accent', (
    tester,
  ) async {
    final theme = resolveTheme('auris')(Brightness.dark, isCompact: false);
    await tester.pumpWidget(favoriteHost(theme));
    await tester.pumpAndSettle();

    final star = tester.widget<Icon>(find.byIcon(Icons.star));
    expect(star.color, theme.colorScheme.primary);
    expect(
      star.color,
      isNot(theme.colorScheme.surface),
      reason: 'star must not match the surface/background color',
    );
  });

  // Regression: leaf request rows had no DragTarget, so dropping a request onto
  // another request inside a folder fell through to the list-level root target
  // and moved it to the ROOT. A leaf drop must land in the target's folder.
  testWidgets(
    'dropping a request onto a request inside a folder moves it into that '
    'folder, not to the root',
    (tester) async {
      const draggedId = 'dragged';
      final tree = <CollectionNodeEntity>[
        const CollectionNodeEntity(
          id: 'f1',
          name: 'Folder1',
          children: [requestNode], // req-1 lives inside Folder1
        ),
        const CollectionNodeEntity(
          id: draggedId,
          name: 'Dragged',
          isFolder: false,
          config: HttpRequestConfigEntity(id: draggedId),
        ),
      ];
      when(() => repo.getCollections()).thenAnswer((_) async => tree);

      final bloc = buildBloc()..add(const LoadCollections());

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<CollectionsBloc>.value(
              value: bloc,
              child: const CollectionNodeRow(
                node: requestNode, // the leaf that lives inside Folder1
                isExpanded: false,
                depth: 1,
                onToggle: _noop,
                rowWidth: 300,
                rowHeight: 44,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragTarget = tester.widget<DragTarget<String>>(
        find.byType(DragTarget<String>),
      );
      dragTarget.onAcceptWithDetails!(
        DragTargetDetails<String>(data: draggedId, offset: Offset.zero),
      );
      // Let the MoveNode handler emit, then fire the bloc's debounced-save
      // timer so no timer is left pending when the widget tree is disposed.
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final folder = bloc.state.collections.firstWhere((n) => n.id == 'f1');
      expect(
        folder.children.map((c) => c.id),
        containsAll(<String>['req-1', draggedId]),
        reason: 'dragged request should land inside Folder1',
      );
      expect(
        bloc.state.collections.map((n) => n.id),
        isNot(contains(draggedId)),
        reason: 'dragged request should no longer be at the root',
      );
    },
  );
}

void _noop() {}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
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
}

void _noop() {}

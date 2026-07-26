// Widget tests for ExampleMenu's A1 instant-delete + UNDO flow: DELETE no
// longer shows a ConfirmDialog; the example is removed immediately and a 5s
// UNDO snackbar restores it at its original index via RestoreExample.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/example_menu.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

final _ex1 = SavedExampleEntity(
  id: 'e1',
  name: 'First Example',
  capturedAt: DateTime(2026),
  config: const HttpRequestConfigEntity(id: 'e1'),
);
final _ex2 = SavedExampleEntity(
  id: 'e2',
  name: 'Second Example',
  capturedAt: DateTime(2026),
  config: const HttpRequestConfigEntity(id: 'e2'),
);

final _node = CollectionNodeEntity(
  id: 'r1',
  name: 'GetThing',
  isFolder: false,
  config: const HttpRequestConfigEntity(id: 'r1'),
  examples: [_ex1, _ex2],
);

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  Future<CollectionsBloc> pumpMenu(WidgetTester tester) async {
    final bloc = CollectionsBloc(
      getCollectionsUseCase: GetCollectionsUseCase(repo),
      saveCollectionsUseCase: SaveCollectionsUseCase(repo),
      saveDebounce: const Duration(milliseconds: 5),
    )..add(ReplaceCollections([_node]));
    await bloc.stream.first;

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: BlocProvider.value(
            value: bloc,
            child: const ExampleMenu(
              nodeId: 'r1',
              exampleId: 'e1',
              exampleName: 'First Example',
            ),
          ),
        ),
      ),
    );
    return bloc;
  }

  Future<void> openAndDelete(WidgetTester tester) async {
    await tester.tap(find.byType(ExampleMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle(); // Wait for snackbar entrance animation
  }

  testWidgets('DELETE removes the example instantly — no ConfirmDialog', (
    tester,
  ) async {
    final bloc = await pumpMenu(tester);
    addTearDown(bloc.close);

    await openAndDelete(tester);

    expect(find.text('Delete example?'), findsNothing);
    final node = CollectionsTreeHelper.findNode(bloc.state.collections, 'r1')!;
    expect(node.examples.map((e) => e.id).toList(), ['e2']);
    expect(find.text('Deleted "First Example"'), findsOneWidget);
    expect(find.text('UNDO'), findsOneWidget);
  });

  testWidgets('UNDO restores the example at its original index', (
    tester,
  ) async {
    final bloc = await pumpMenu(tester);
    addTearDown(bloc.close);

    await openAndDelete(tester);
    expect(find.text('UNDO'), findsOneWidget); // Snackbar should be visible
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    final node = CollectionsTreeHelper.findNode(bloc.state.collections, 'r1')!;
    expect(node.examples.map((e) => e.id).toList(), ['e1', 'e2']);
    expect(node.examples.first, _ex1);
  });
}

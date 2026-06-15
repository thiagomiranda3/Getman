// Widget test for the H2 fix: the collections tree must keep folders expanded
// across an unrelated mutation (rename/add/favorite). The TreeController keys
// expansion by node identity; mutations rebuild non-equal CollectionNodeEntity
// objects (copyWith rewrites the ancestor chain), so expansion was lost. The
// fix keys expansion by node.id.

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
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc build() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
    saveDebounce: const Duration(milliseconds: 5),
  );

  testWidgets('folder stays expanded after a child inside it is renamed', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);

    const child = CollectionNodeEntity(
      id: 'C',
      name: 'ChildReq',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'C'),
    );
    const folder = CollectionNodeEntity(
      id: 'F',
      name: 'Folder',
      children: [child],
    );
    const sibling = CollectionNodeEntity(
      id: 'S',
      name: 'Sibling',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'S'),
    );

    bloc.add(const ReplaceCollections([folder, sibling]));
    await bloc.stream.first;

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: BlocProvider.value(value: bloc, child: const CollectionsList()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Folder is collapsed initially → its child is not rendered.
    expect(find.text('CHILDREQ'), findsNothing);

    // Expand the folder.
    await tester.tap(find.text('FOLDER'));
    await tester.pumpAndSettle();
    expect(find.text('CHILDREQ'), findsOneWidget);

    // Rename the child *inside* the folder. This rewrites the folder's
    // ancestor chain into a non-equal entity — the case that collapsed it.
    bloc.add(const RenameNode('C', 'ChildRenamed'));
    await bloc.stream.first;
    await tester.pumpAndSettle();

    // The folder must still be expanded, showing the renamed child.
    expect(find.text('CHILDRENAMED'), findsOneWidget);
  });
}

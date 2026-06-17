import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/collections/presentation/widgets/collection_variables_dialog.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeCollectionsEvent());
  });

  testWidgets('SAVE dispatches UpdateNodeVariables for the node', (
    tester,
  ) async {
    final bloc = MockCollectionsBloc();
    when(() => bloc.state).thenReturn(CollectionsState());

    const node = CollectionNodeEntity(
      id: 'f1',
      name: 'API',
      variables: {'base': 'x'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
        home: BlocProvider<CollectionsBloc>.value(
          value: bloc,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      CollectionVariablesDialog.show(context, node),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    final captured = verify(() => bloc.add(captureAny())).captured;
    final event = captured.whereType<UpdateNodeVariables>().single;
    expect(event.id, 'f1');
    expect(event.variables, {'base': 'x'});
  });
}

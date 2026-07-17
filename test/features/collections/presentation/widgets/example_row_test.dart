import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/presentation/widgets/example_row.dart';
import 'package:getman/features/collections/presentation/widgets/node_drag_data.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

const _savedConfigId = 'saved-req-1';

final _example = SavedExampleEntity(
  id: 'ex-1',
  name: 'Example One',
  capturedAt: DateTime(2026),
  config: const HttpRequestConfigEntity(
    id: _savedConfigId,
    url: 'https://api.example.com/thing',
  ),
);

Widget _host(TabsBloc bloc) {
  return MaterialApp(
    theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
    home: Scaffold(
      body: BlocProvider<TabsBloc>.value(
        value: bloc,
        child: ExampleRow(
          nodeId: 'node-1',
          nodeName: 'GetThing',
          example: _example,
          depth: 0,
          rowWidth: 300,
          rowHeight: 44,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
  });

  late MockTabsBloc bloc;

  setUp(() {
    bloc = MockTabsBloc();
    when(() => bloc.state).thenReturn(const TabsState());
  });

  // D3 regression: opening a saved example used to keep the original saved
  // request's config id, so chaining rules (assertions/extractions) added
  // from the opened tab silently aliased the ORIGINAL saved request's rules.
  testWidgets(
    'tapping the row opens a tab with a FRESH config id, not the saved '
    "example's id (D3 — chaining-rule aliasing)",
    (tester) async {
      await tester.pumpWidget(_host(bloc));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Example One'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => bloc.add(captureAny(that: isA<AddTab>())),
      ).captured;
      expect(captured, hasLength(1));
      final event = captured.first as AddTab;
      expect(event.config, isNotNull);
      expect(
        event.config!.id,
        isNot(_savedConfigId),
        reason:
            'a fresh id must be minted so this tab has its own chaining '
            "rules, independent of the saved request's",
      );
      // Everything else about the config is preserved verbatim.
      expect(event.config!.url, _example.config.url);
      expect(event.collectionName, 'GetThing · Example One');
    },
  );

  testWidgets(
    'a collection-node drag (NodeDragData) does not error when released over '
    'an example row (D4 — swallow-target typing)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<TabsBloc>.value(
              value: bloc,
              child: Column(
                children: [
                  const LongPressDraggable<NodeDragData>(
                    key: ValueKey('node_drag_source'),
                    data: NodeDragData('other-node'),
                    feedback: Material(child: Text('other-node')),
                    child: SizedBox(
                      width: 100,
                      height: 50,
                      child: ColoredBox(color: Colors.orange),
                    ),
                  ),
                  ExampleRow(
                    nodeId: 'node-1',
                    nodeName: 'GetThing',
                    example: _example,
                    depth: 0,
                    rowWidth: 300,
                    rowHeight: 44,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sourceCenter = tester.getCenter(
        find.byKey(const ValueKey('node_drag_source')),
      );
      final targetCenter = tester.getCenter(find.byType(ExampleRow));
      final gesture = await tester.startGesture(sourceCenter);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(targetCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}

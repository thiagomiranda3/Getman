import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_view.dart';

Widget _host(Object? data) => MaterialApp(
  theme: brutalistTheme(Brightness.light),
  home: Scaffold(body: JsonTreeView(data: data)),
);

void main() {
  group('JsonTreeView', () {
    testWidgets('renders top-level keys with nested objects expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host({
          'name': 'Ada',
          'addr': {'zip': '900'},
        }),
      );

      expect(find.text('name'), findsOneWidget);
      expect(find.text('addr'), findsOneWidget);
      // Top-level containers expand by default, so the nested key shows.
      expect(find.text('zip'), findsOneWidget);
    });

    testWidgets('tapping a container row collapses its children', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host({
          'addr': {'zip': '900'},
        }),
      );
      expect(find.text('zip'), findsOneWidget);

      await tester.tap(find.text('addr'));
      await tester.pumpAndSettle();

      expect(find.text('zip'), findsNothing);
    });

    testWidgets('renders array indices', (tester) async {
      await tester.pumpWidget(
        _host({
          'items': ['a', 'b'],
        }),
      );
      expect(find.text('[0]'), findsOneWidget);
      expect(find.text('[1]'), findsOneWidget);
    });

    testWidgets('copy path puts the JSONPath on the clipboard', (tester) async {
      final clips = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clips.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        _host({
          'user': {'id': 7},
        }),
      );

      await tester.tap(find.byKey(const ValueKey(r'tree_menu_$.user.id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy path'));
      await tester.pumpAndSettle();

      expect(clips, contains(r'$.user.id'));
    });

    testWidgets('extract action reports the node JSONPath', (tester) async {
      final extracted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: JsonTreeView(
              data: const {
                'user': {'id': 7},
              },
              onExtract: extracted.add,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey(r'tree_menu_$.user.id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extract to {{var}}'));
      await tester.pumpAndSettle();

      expect(extracted, [r'$.user.id']);
    });

    testWidgets('no extract action when onExtract is null', (tester) async {
      await tester.pumpWidget(_host(const {'a': 1}));
      await tester.tap(find.byKey(const ValueKey(r'tree_menu_$.a')));
      await tester.pumpAndSettle();
      expect(find.text('Extract to {{var}}'), findsNothing);
    });
  });
}

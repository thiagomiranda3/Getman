// test/features/collections/presentation/widgets/spec_import_preview_test.dart
// Direct widget tests for SpecImportPreview: root-level leaf rows, the
// tristate folder checkbox, the environments summary line, and warnings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_preview.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

const _leafA = CollectionNodeEntity(
  id: 'u1',
  name: 'List users',
  isFolder: false,
  config: HttpRequestConfigEntity(id: 'c1', url: 'https://x/users'),
);
const _leafB = CollectionNodeEntity(
  id: 'u2',
  name: 'Create user',
  isFolder: false,
  config: HttpRequestConfigEntity(
    id: 'c2',
    url: 'https://x/users',
    method: 'POST',
  ),
);
const _folder = CollectionNodeEntity(
  id: 'f1',
  name: 'Users',
  children: [_leafA, _leafB],
);

/// A root-level request leaf (no folder), the branch the two-folder importer
/// fixture never produces.
const _rootLeaf = CollectionNodeEntity(
  id: 'h1',
  name: 'Health',
  isFolder: false,
  config: HttpRequestConfigEntity(id: 'c3', url: 'https://x/health'),
);

const _root = CollectionNodeEntity(
  id: 'root',
  name: 'Demo',
  children: [_folder, _rootLeaf],
);

void main() {
  final toggledFolders = <(String, bool)>[];
  final toggledLeaves = <(String, bool)>[];

  setUp(() {
    toggledFolders.clear();
    toggledLeaves.clear();
  });

  Future<void> pump(
    WidgetTester tester, {
    required Set<String> selected,
    List<EnvironmentEntity> environments = const [],
    List<String> warnings = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpecImportPreview(
              result: ImportResult(
                root: _root,
                environments: environments,
                warnings: warnings,
              ),
              selected: selected,
              onToggleFolder: (folder, {required select}) =>
                  toggledFolders.add((folder.id, select)),
              onToggleLeaf: (id, {required select}) =>
                  toggledLeaves.add((id, select)),
            ),
          ),
        ),
      ),
    );
  }

  Checkbox checkboxNear(WidgetTester tester, String label) {
    return tester.widget<Checkbox>(
      find
          .descendant(
            of: find.ancestor(
              of: find.text(label),
              matching: find.byType(Row),
            ),
            matching: find.byType(Checkbox),
          )
          .first,
    );
  }

  testWidgets('renders folder, indented leaves and a root-level leaf', (
    tester,
  ) async {
    await pump(tester, selected: {'u1', 'u2', 'h1'});

    expect(find.text('Users'), findsOneWidget);
    expect(find.text('List users'), findsOneWidget);
    expect(find.text('Create user'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
    // Method badges come from each leaf's config.
    expect(find.text('POST'), findsOneWidget);
    expect(find.text('GET'), findsNWidgets(2));
    expect(find.text('Creates no environments.'), findsOneWidget);
  });

  testWidgets('a partially selected folder shows the tristate dash and '
      'tapping it selects the whole group', (tester) async {
    await pump(tester, selected: {'u1'});

    expect(checkboxNear(tester, 'Users').value, isNull); // partial

    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Users'),
              matching: find.byType(Row),
            ),
            matching: find.byType(Checkbox),
          )
          .first,
    );
    expect(toggledFolders, [('f1', true)]);
  });

  testWidgets('a fully selected folder unchecks the whole group on tap', (
    tester,
  ) async {
    await pump(tester, selected: {'u1', 'u2'});

    expect(checkboxNear(tester, 'Users').value, isTrue);

    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Users'),
              matching: find.byType(Row),
            ),
            matching: find.byType(Checkbox),
          )
          .first,
    );
    expect(toggledFolders, [('f1', false)]);
  });

  testWidgets('tapping a selected root-level leaf deselects it', (
    tester,
  ) async {
    await pump(tester, selected: {'h1'});

    expect(checkboxNear(tester, 'Health').value, isTrue);

    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Health'),
              matching: find.byType(Row),
            ),
            matching: find.byType(Checkbox),
          )
          .first,
    );
    expect(toggledLeaves, [('h1', false)]);
  });

  testWidgets('lists created environments by name', (tester) async {
    await pump(
      tester,
      selected: {'u1'},
      environments: [
        EnvironmentEntity(id: 'e1', name: 'Prod'),
        EnvironmentEntity(id: 'e2', name: 'Staging'),
      ],
    );

    expect(
      find.text('Creates 2 environment(s): Prod, Staging'),
      findsOneWidget,
    );
  });

  testWidgets('renders import warnings with a warning icon', (tester) async {
    await pump(
      tester,
      selected: {'u1'},
      warnings: const ['GET /users: cookie apiKey auth is not supported'],
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      find.text('GET /users: cookie apiKey auth is not supported'),
      findsOneWidget,
    );
  });
}

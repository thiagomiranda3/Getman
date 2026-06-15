import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/datasources/workspace_data_source_factory.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

void main() {
  late Directory tmp;
  late WorkspaceCollectionsDataSource ds;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('getman_ws_test');
    ds = createWorkspaceDataSource();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'write then read round-trips a nested tree and drops response fields',
    () async {
      final forest = [
        const CollectionNodeEntity(
          id: 'f1',
          name: 'Auth',
          children: [
            CollectionNodeEntity(
              id: 'r1',
              name: 'Login',
              isFolder: false,
              config: HttpRequestConfigEntity(
                id: 'c1',
                method: 'POST',
                url: 'https://api.dev/login',
                responseBody: 'SECRET',
                statusCode: 200,
              ),
            ),
          ],
        ),
        const CollectionNodeEntity(
          id: 'r2',
          name: 'Ping',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'c2',
            url: 'https://api.dev/ping',
          ),
        ),
      ];

      await ds.write(tmp.path, forest);

      // Response fields never reach disk.
      final loginFile = File('${tmp.path}/auth/login.req.json');
      expect(loginFile.existsSync(), isTrue);
      expect(loginFile.readAsStringSync(), isNot(contains('SECRET')));

      final back = await ds.read(tmp.path);
      expect(back, hasLength(2));
      final auth = back.firstWhere((n) => n.name == 'Auth');
      expect(auth.isFolder, isTrue);
      expect(auth.children.single.name, 'Login');
      expect(auth.children.single.config!.method, 'POST');
      expect(auth.children.single.config!.responseBody, isNull);
      final ping = back.firstWhere((n) => n.name == 'Ping');
      expect(ping.config!.url, 'https://api.dev/ping');
    },
  );

  test('reconcile deletes orphaned request files on the next write', () async {
    await ds.write(tmp.path, const [
      CollectionNodeEntity(
        id: 'r1',
        name: 'Keep',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'c1'),
      ),
      CollectionNodeEntity(
        id: 'r2',
        name: 'Drop',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'c2'),
      ),
    ]);
    expect(File('${tmp.path}/drop.req.json').existsSync(), isTrue);

    await ds.write(tmp.path, const [
      CollectionNodeEntity(
        id: 'r1',
        name: 'Keep',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'c1'),
      ),
    ]);
    expect(File('${tmp.path}/drop.req.json').existsSync(), isFalse);
    expect(File('${tmp.path}/keep.req.json').existsSync(), isTrue);
  });

  test('reading a non-existent workspace returns empty', () async {
    final back = await ds.read('${tmp.path}/does-not-exist');
    expect(back, isEmpty);
  });
}

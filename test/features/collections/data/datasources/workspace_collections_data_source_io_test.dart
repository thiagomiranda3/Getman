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

  test('reading a non-existent workspace root throws (never masquerades as '
      'an empty workspace)', () async {
    // Returning [] for a missing root (unmounted drive, deleted folder) would
    // let a reload-from-disk wipe the whole in-app tree.
    await expectLater(
      ds.read('${tmp.path}/does-not-exist'),
      throwsA(isA<FileSystemException>()),
    );
  });

  group('reconcile matches names case-insensitively', () {
    // On a case-insensitive filesystem (macOS default) a case-mismatched
    // pre-existing entry ABSORBS the write under its old-case name: the
    // rename onto `login.req.json` keeps `Login.req.json`, and creating
    // `payments/` next to `Payments/` is a no-op. A literal-case compare in
    // reconcile then deleted the very entry that received the write. These
    // tests hold on case-sensitive filesystems too: there the old-case
    // entries are genuine siblings, and case-insensitive matching must keep
    // them rather than delete them.
    test('a case-mismatched request file survives the mirror write', () async {
      File('${tmp.path}/Login.req.json').writeAsStringSync(
        '{"id":"old","name":"Login","request":{"id":"old",'
        '"url":"https://old.dev"}}',
      );

      await ds.write(tmp.path, const [
        CollectionNodeEntity(
          id: 'r1',
          name: 'Login',
          isFolder: false,
          config: HttpRequestConfigEntity(id: 'c1', url: 'https://api.dev'),
        ),
      ]);

      // Resolves to the absorbing file on APFS and to the old-case sibling
      // on a case-sensitive filesystem — it must exist either way.
      expect(File('${tmp.path}/Login.req.json').existsSync(), isTrue);
      final back = await ds.read(tmp.path);
      expect(back.map((n) => n.name), contains('Login'));
    });

    test('a case-mismatched folder (and hand-placed extras inside) survives '
        'the mirror write', () async {
      Directory('${tmp.path}/Payments').createSync();
      File('${tmp.path}/Payments/.folder.json').writeAsStringSync(
        '{"id":"old-f","name":"Payments","childOrder":[]}',
      );
      File('${tmp.path}/Payments/notes.md').writeAsStringSync('hand-placed');

      await ds.write(tmp.path, const [
        CollectionNodeEntity(id: 'f1', name: 'Payments'),
      ]);

      expect(Directory('${tmp.path}/Payments').existsSync(), isTrue);
      expect(File('${tmp.path}/Payments/notes.md').existsSync(), isTrue);
      final back = await ds.read(tmp.path);
      expect(back.map((n) => n.name), contains('Payments'));
    });
  });

  test('a case-mismatched order-manifest entry still positions its node — '
      'not dumped into the appended-at-the-end bucket', () async {
    // Disk holds capitalized names (e.g. a case-only rename landed via git
    // on a case-insensitive filesystem) while the manifest recorded the
    // lower-case slugs the mirror wrote.
    File('${tmp.path}/Zeta.req.json').writeAsStringSync(
      '{"id":"z","name":"Zeta","request":{"id":"z","url":"https://z.dev"}}',
    );
    File('${tmp.path}/alpha.req.json').writeAsStringSync(
      '{"id":"a","name":"alpha","request":{"id":"a","url":"https://a.dev"}}',
    );
    Directory('${tmp.path}/.getman').createSync();
    File('${tmp.path}/.getman/workspace.json').writeAsStringSync(
      '{"version":1,"rootOrder":["zeta","alpha"]}',
    );

    final back = await ds.read(tmp.path);

    // An exact-only lookup missed "zeta" and appended Zeta AFTER alpha,
    // silently reordering the tree on every such read.
    expect(back.map((n) => n.name).toList(), ['Zeta', 'alpha']);
  });

  test('a folder dir and a request file sharing one slug both survive a read '
      '(clean git merge shape)', () async {
    Directory('${tmp.path}/foo').createSync();
    File('${tmp.path}/foo/.folder.json').writeAsStringSync(
      '{"id":"d1","name":"Shared","childOrder":[]}',
    );
    File('${tmp.path}/foo.req.json').writeAsStringSync(
      '{"id":"r1","name":"Foo Req","request":{"id":"c1", '
      '"url":"https://api.dev/foo"}}',
    );
    Directory('${tmp.path}/.getman').createSync();
    File('${tmp.path}/.getman/workspace.json').writeAsStringSync(
      '{"version":1,"rootOrder":["foo"]}',
    );

    final back = await ds.read(tmp.path);

    expect(back, hasLength(2));
    expect(back.where((n) => n.isFolder).single.name, 'Shared');
    expect(back.where((n) => !n.isFolder).single.name, 'Foo Req');
  });

  test('duplicate node ids across files are re-minted on read (node id and '
      'config id), files left untouched', () async {
    // Hand-copied file (`cp login.req.json signup.req.json`) duplicates ids
    // verbatim — id-keyed mutations would hit both, deletes remove both.
    const json =
        '{"id":"dup","name":"Copied","request":{"id":"cdup",'
        '"url":"https://api.dev"}}';
    File('${tmp.path}/login.req.json').writeAsStringSync(json);
    File('${tmp.path}/signup.req.json').writeAsStringSync(json);

    final back = await ds.read(tmp.path);

    expect(back, hasLength(2));
    expect(back[0].id, isNotEmpty);
    expect(back[1].id, isNotEmpty);
    expect(back[0].id, isNot(back[1].id));
    expect(back[0].config!.id, isNot(back[1].config!.id));
    // The files stay as-is — the next mirror rewrites them with the new id.
    expect(
      File('${tmp.path}/login.req.json').readAsStringSync(),
      contains('"dup"'),
    );
    expect(
      File('${tmp.path}/signup.req.json').readAsStringSync(),
      contains('"dup"'),
    );
  });

  test('an empty node id is re-minted on read', () async {
    File('${tmp.path}/blank.req.json').writeAsStringSync(
      '{"id":"","name":"Blank","request":{"id":"",'
      '"url":"https://api.dev"}}',
    );

    final back = await ds.read(tmp.path);

    expect(back.single.id, isNotEmpty);
  });

  test('reconciling an orphaned folder keeps foreign files and the directory '
      'holding them', () async {
    await ds.write(tmp.path, const [
      CollectionNodeEntity(
        id: 'f1',
        name: 'Temp',
        children: [
          CollectionNodeEntity(
            id: 'r1',
            name: 'Ping',
            isFolder: false,
            config: HttpRequestConfigEntity(id: 'c1'),
          ),
          CollectionNodeEntity(id: 'f2', name: 'Inner'),
        ],
      ),
    ]);
    File('${tmp.path}/temp/notes.md').writeAsStringSync('hand-placed');

    await ds.write(tmp.path, const []);

    // Getman-owned entries are gone…
    expect(File('${tmp.path}/temp/.folder.json').existsSync(), isFalse);
    expect(File('${tmp.path}/temp/ping.req.json').existsSync(), isFalse);
    expect(Directory('${tmp.path}/temp/inner').existsSync(), isFalse);
    // …but the foreign file and the directory holding it survive.
    expect(File('${tmp.path}/temp/notes.md').existsSync(), isTrue);
    expect(Directory('${tmp.path}/temp').existsSync(), isTrue);
  });

  test('reconciling an orphaned folder with only getman content removes it '
      'entirely', () async {
    await ds.write(tmp.path, const [
      CollectionNodeEntity(
        id: 'f1',
        name: 'Gone',
        children: [
          CollectionNodeEntity(
            id: 'r1',
            name: 'Ping',
            isFolder: false,
            config: HttpRequestConfigEntity(id: 'c1'),
          ),
        ],
      ),
    ]);

    await ds.write(tmp.path, const []);

    expect(Directory('${tmp.path}/gone').existsSync(), isFalse);
  });
}

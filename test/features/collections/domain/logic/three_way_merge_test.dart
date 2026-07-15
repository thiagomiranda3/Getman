import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/three_way_merge.dart';

CollectionNodeEntity _leaf({
  String id = 'r1',
  String name = 'Req',
  bool isFavorite = false,
  String method = 'GET',
  String url = '',
  Map<String, String> headers = const {},
  String body = '',
  Map<String, String> auth = const {},
  BodyType bodyType = BodyType.raw,
  List<MultipartFieldEntity> formFields = const [],
  String? bodyFilePath,
  String graphqlVariables = '',
}) => CollectionNodeEntity(
  id: id,
  name: name,
  isFolder: false,
  isFavorite: isFavorite,
  config: HttpRequestConfigEntity(
    id: id,
    method: method,
    url: url,
    headers: headers,
    body: body,
    auth: auth,
    bodyType: bodyType,
    formFields: formFields,
    bodyFilePath: bodyFilePath,
    graphqlVariables: graphqlVariables,
  ),
);

CollectionNodeEntity _folder({
  String id = 'f1',
  String name = 'Folder',
  bool isFavorite = false,
  Map<String, String> variables = const {},
  Set<String> secretKeys = const {},
  List<CollectionNodeEntity> children = const [],
}) => CollectionNodeEntity(
  id: id,
  name: name,
  isFavorite: isFavorite,
  variables: variables,
  secretKeys: secretKeys,
  children: children,
);

void main() {
  group('ThreeWayMerge.mergeRequest — scalars', () {
    test('non-overlapping scalar edits auto-merge with no conflict', () {
      final base = _leaf(url: 'a');
      final incoming = _leaf(url: 'b'); // changed url
      final yours = _leaf(url: 'a', method: 'POST'); // changed method
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts, isEmpty);
      expect(r.merged.config!.url, 'b');
      expect(r.merged.config!.method, 'POST');
    });

    test('a true url overlap is one conflict', () {
      final r = ThreeWayMerge.mergeRequest(
        _leaf(url: 'a'),
        _leaf(url: 'b'),
        _leaf(url: 'c'),
      );
      expect(r.conflicts.map((c) => c.field), ['url']);
      expect(r.conflicts.single.incoming, 'b');
      expect(r.conflicts.single.yours, 'c');
      // Unresolved scalar stays at the incoming value in the merged entity.
      expect(r.merged.config!.url, 'b');
    });

    test('identical edits on both sides agree with no conflict', () {
      final base = _leaf();
      final incoming = _leaf(method: 'POST');
      final yours = _leaf(method: 'POST');
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts, isEmpty);
      expect(r.merged.config!.method, 'POST');
    });

    test(
      'name and isFavorite (leaf top-level scalars) follow the same rule',
      () {
        final base = _leaf(name: 'Old');
        final incoming = _leaf(name: 'New'); // renamed
        final yours = _leaf(name: 'Old', isFavorite: true); // favorited
        final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
        expect(r.conflicts, isEmpty);
        expect(r.merged.name, 'New');
        expect(r.merged.isFavorite, isTrue);
      },
    );

    test('bodyType is merged as a scalar over its wire string', () {
      final base = _leaf();
      final incoming = _leaf();
      final yours = _leaf(bodyType: BodyType.graphql);
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts, isEmpty);
      expect(r.merged.config!.bodyType, BodyType.graphql);
    });
  });

  group('ThreeWayMerge.mergeRequest — maps', () {
    test('different header keys auto-merge (union, no conflict)', () {
      final base = _leaf(headers: const {'A': '1'});
      final incoming = _leaf(headers: const {'A': '1', 'B': '2'});
      final yours = _leaf(headers: const {'A': '1', 'C': '3'});
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts, isEmpty);
      expect(r.merged.config!.headers, {'A': '1', 'B': '2', 'C': '3'});
    });

    test('same header key changed differently on both sides collides', () {
      final base = _leaf(headers: const {'X': '1'});
      final incoming = _leaf(headers: const {'X': '2'});
      final yours = _leaf(headers: const {'X': '3'});
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts.map((c) => c.field), ["header 'X'"]);
      expect(r.conflicts.single.kind, FieldConflictKind.mapEntry);
      expect(r.conflicts.single.incoming, '2');
      expect(r.conflicts.single.yours, '3');
      expect(r.merged.config!.headers['X'], '2');
    });

    test(
      'header deleted on incoming but unchanged on yours auto-merges to '
      'deletion (no conflict)',
      () {
        final base = _leaf(headers: const {'X': '1'});
        final incoming = _leaf(); // deleted X
        final yours = _leaf(headers: const {'X': '1'}); // unchanged
        final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
        expect(r.conflicts, isEmpty);
        expect(r.merged.config!.headers.containsKey('X'), isFalse);
      },
    );

    test(
      'header deleted on incoming but edited on yours is a conflict',
      () {
        final base = _leaf(headers: const {'X': '1'});
        final incoming = _leaf(); // deleted X
        final yours = _leaf(headers: const {'X': '2'}); // edited X
        final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
        expect(r.conflicts.map((c) => c.field), ["header 'X'"]);
        expect(r.conflicts.single.kind, FieldConflictKind.mapEntry);
        expect(r.conflicts.single.incoming, isNull);
        expect(r.conflicts.single.yours, '2');
      },
    );
  });

  group('ThreeWayMerge.mergeRequest — opaque fields', () {
    test('auth conflict carries null values (opaque)', () {
      final base = _leaf(auth: const {'type': 'none'});
      final incoming = _leaf(auth: const {'type': 'bearer', 'token': 't1'});
      final yours = _leaf(auth: const {'type': 'basic', 'user': 'u'});
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts.map((c) => c.field), ['authentication']);
      expect(r.conflicts.single.kind, FieldConflictKind.opaque);
      expect(r.conflicts.single.incoming, isNull);
      expect(r.conflicts.single.yours, isNull);
      expect(r.merged.config!.auth, incoming.config!.auth);
    });

    test('auth auto-merges when only one side changed it', () {
      final base = _leaf();
      final incoming = _leaf();
      final yours = _leaf(auth: const {'type': 'bearer', 'token': 't1'});
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts, isEmpty);
      expect(r.merged.config!.auth, yours.config!.auth);
    });

    test('formFields conflict carries null values (whole-field)', () {
      final base = _leaf();
      final incoming = _leaf(
        formFields: const [MultipartFieldEntity(name: 'a', value: '1')],
      );
      final yours = _leaf(
        formFields: const [MultipartFieldEntity(name: 'b', value: '2')],
      );
      final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
      expect(r.conflicts.map((c) => c.field), ['form fields']);
      expect(r.conflicts.single.kind, FieldConflictKind.list);
      expect(r.conflicts.single.incoming, isNull);
      expect(r.conflicts.single.yours, isNull);
    });
  });

  group('ThreeWayMerge.mergeRequest — add/add (base null)', () {
    test(
      'both sides added the same path with different content: '
      'conflicts, no crash',
      () {
        final incoming = _leaf(url: 'https://a');
        final yours = _leaf(url: 'https://b', method: 'POST');
        final r = ThreeWayMerge.mergeRequest(null, incoming, yours);
        expect(
          r.conflicts.map((c) => c.field),
          containsAll(['url', 'method']),
        );
        expect(r.merged.config!.url, 'https://a');
        expect(r.merged.config!.method, 'GET');
      },
    );

    test('add/add with identical content agrees with no conflict', () {
      final incoming = _leaf(url: 'https://same');
      final yours = _leaf(url: 'https://same');
      final r = ThreeWayMerge.mergeRequest(null, incoming, yours);
      expect(r.conflicts, isEmpty);
      expect(r.merged.config!.url, 'https://same');
    });
  });

  group('ThreeWayMerge.mergeRequest — zero-true-conflict file', () {
    test(
      'fully auto-resolvable file: conflicts.isEmpty and merged carries '
      'both sides',
      () {
        final base = _leaf(
          url: 'https://api.dev',
          headers: const {'A': '1'},
        );
        final incoming = _leaf(
          url: 'https://api.dev/v2', // incoming changed url
          headers: const {'A': '1', 'B': '2'}, // incoming added header
        );
        final yours = _leaf(
          url: 'https://api.dev',
          method: 'POST', // yours changed method
          headers: const {'A': '1', 'C': '3'}, // yours added header
        );
        final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
        expect(r.conflicts, isEmpty);
        expect(r.merged.config!.url, 'https://api.dev/v2');
        expect(r.merged.config!.method, 'POST');
        expect(r.merged.config!.headers, {'A': '1', 'B': '2', 'C': '3'});
      },
    );
  });

  group('ThreeWayMerge.mergeFolder', () {
    test('folder scalar/map fields follow the same 3-way rule', () {
      final base = _folder(name: 'Old', variables: const {'A': '1'});
      final incoming = _folder(
        name: 'New',
        variables: const {'A': '1', 'B': '2'},
      );
      final yours = _folder(name: 'Old', variables: const {'A': '1', 'C': '3'});
      final r = ThreeWayMerge.mergeFolder(
        base,
        ['x'],
        incoming,
        ['x'],
        yours,
        ['x'],
      );
      expect(r.conflicts, isEmpty);
      expect(r.merged.name, 'New');
      expect(r.merged.variables, {'A': '1', 'B': '2', 'C': '3'});
    });

    test(
      'divergent childOrder on both sides is a single "child order" conflict',
      () {
        final base = _folder();
        final incoming = _folder();
        final yours = _folder();
        final r = ThreeWayMerge.mergeFolder(
          base,
          ['A', 'B'],
          incoming,
          ['A', 'B', 'C'],
          yours,
          ['A', 'X', 'B'],
        );
        expect(r.conflicts.map((c) => c.field), ['child order']);
        expect(r.conflicts.single.kind, FieldConflictKind.scalar);
        expect(r.conflicts.single.incoming, 'A, B, C');
        expect(r.conflicts.single.yours, 'A, X, B');
      },
    );

    test(
      'only one side reordering auto-merges childOrder with no conflict',
      () {
        final base = _folder();
        final incoming = _folder();
        final yours = _folder();
        final r = ThreeWayMerge.mergeFolder(
          base,
          ['A'],
          incoming,
          ['A', 'B'],
          yours,
          ['A'],
        );
        expect(r.conflicts, isEmpty);
      },
    );

    test('secretKeys collision carries null values (whole-field)', () {
      final base = _folder();
      final incoming = _folder(secretKeys: const {'token'});
      final yours = _folder(secretKeys: const {'apiKey'});
      final r = ThreeWayMerge.mergeFolder(
        base,
        const [],
        incoming,
        const [],
        yours,
        const [],
      );
      expect(r.conflicts.map((c) => c.field), ['secret keys']);
      expect(r.conflicts.single.kind, FieldConflictKind.list);
      expect(r.conflicts.single.incoming, isNull);
      expect(r.conflicts.single.yours, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

void main() {
  HttpRequestConfigEntity cfg({
    String method = 'GET',
    String url = 'https://api.dev',
    Map<String, String> headers = const {},
    String body = '',
    Map<String, String> auth = const {},
    RequestKind kind = RequestKind.http,
  }) => HttpRequestConfigEntity(
    id: 'c',
    method: method,
    url: url,
    headers: headers,
    body: body,
    auth: auth,
    kind: kind,
  );

  group('RequestConfigDiff', () {
    test('added request reports every non-empty field as added', () {
      final d = RequestConfigDiff.diff(null, cfg(method: 'POST'));
      expect(
        d.changes.any((c) => c.field == 'method' && c.kind == ChangeKind.added),
        isTrue,
      );
    });

    test('method + url changes are reported as changed with before/after', () {
      final d = RequestConfigDiff.diff(
        cfg(),
        cfg(method: 'POST', url: 'https://api.dev/v2'),
      );
      final method = d.changes.firstWhere((c) => c.field == 'method');
      expect(method.kind, ChangeKind.changed);
      expect(method.before, 'GET');
      expect(method.after, 'POST');
      expect(d.changes.any((c) => c.field == 'url'), isTrue);
    });

    test('header add/remove/change reported per key', () {
      final d = RequestConfigDiff.diff(
        cfg(headers: {'A': '1', 'B': '2'}),
        cfg(headers: {'A': '9', 'C': '3'}),
      );
      final labels = d.changes.map((c) => '${c.field}:${c.kind.name}').toSet();
      expect(
        labels,
        containsAll(<String>{
          "header 'A':changed",
          "header 'B':removed",
          "header 'C':added",
        }),
      );
    });

    test('auth change is reported without leaking values', () {
      final d = RequestConfigDiff.diff(
        cfg(auth: {'type': 'bearer', 'token': 'secret1'}),
        cfg(auth: {'type': 'bearer', 'token': 'secret2'}),
      );
      final auth = d.changes.firstWhere((c) => c.field == 'authentication');
      expect(auth.kind, ChangeKind.changed);
      expect(auth.before, isNull);
      expect(auth.after, isNull);
    });

    test('identical configs produce an empty diff', () {
      expect(RequestConfigDiff.diff(cfg(), cfg()).isEmpty, isTrue);
    });

    // Regression: kind IS round-tripped by the serializer (as the enum name,
    // omitted when http) but was previously never diffed, so a kind-only
    // change reviewed as an empty diff.
    test('kind change is reported over the serialized enum names', () {
      final d = RequestConfigDiff.diff(
        cfg(),
        cfg(kind: RequestKind.webSocket),
      );
      final kind = d.changes.singleWhere((c) => c.field == 'kind');
      expect(kind.kind, ChangeKind.changed);
      expect(kind.before, 'http');
      expect(kind.after, 'webSocket');
    });
  });

  group('RequestNodeDiff', () {
    CollectionNodeEntity leaf({String? description}) => CollectionNodeEntity(
      id: 'r',
      name: 'Req',
      isFolder: false,
      description: description,
      config: cfg(),
    );

    // Regression: description IS round-tripped by the serializer but lives
    // on the NODE (not the config), so a description-only change previously
    // reviewed as an empty diff.
    test('a description-only change produces a non-empty diff', () {
      final d = RequestNodeDiff.diff(
        leaf(description: 'old notes'),
        leaf(description: 'new notes'),
      );
      expect(d.isEmpty, isFalse);
      final desc = d.changes.singleWhere((c) => c.field == 'description');
      expect(desc.kind, ChangeKind.changed);
      expect(desc.before, 'old notes');
      expect(desc.after, 'new notes');
    });

    test('config changes are carried alongside the node-level fields', () {
      final before = leaf();
      final after = leaf(
        description: 'notes',
      ).copyWith(config: cfg(method: 'POST'));
      final d = RequestNodeDiff.diff(before, after);
      expect(
        d.changes.map((c) => c.field),
        containsAll(<String>['description', 'method']),
      );
    });

    test('identical nodes produce an empty diff', () {
      expect(
        RequestNodeDiff.diff(
          leaf(description: 'x'),
          leaf(description: 'x'),
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('FolderNodeDiff', () {
    CollectionNodeEntity folder({
      String name = 'F',
      String? description,
      Map<String, String> variables = const {},
      List<CollectionNodeEntity> children = const [],
    }) => CollectionNodeEntity(
      id: 'f',
      name: name,
      description: description,
      children: children,
      variables: variables,
    );

    test('name change reported', () {
      final d = FolderNodeDiff.diff(folder(), folder(name: 'G'));
      final n = d.changes.firstWhere((c) => c.field == 'name');
      expect(n.before, 'F');
      expect(n.after, 'G');
    });

    // Regression: folder descriptions are round-tripped by the serializer
    // but were previously never diffed — a description-only change reviewed
    // as an empty diff.
    test('a description-only change produces a non-empty diff', () {
      final d = FolderNodeDiff.diff(
        folder(description: 'old'),
        folder(description: 'new'),
      );
      expect(d.isEmpty, isFalse);
      final desc = d.changes.singleWhere((c) => c.field == 'description');
      expect(desc.kind, ChangeKind.changed);
      expect(desc.before, 'old');
      expect(desc.after, 'new');
    });

    test('variable add reported per key', () {
      final d = FolderNodeDiff.diff(folder(), folder(variables: {'x': '1'}));
      expect(
        d.changes.any(
          (c) => c.field == "variable 'x'" && c.kind == ChangeKind.added,
        ),
        isTrue,
      );
    });
  });
}

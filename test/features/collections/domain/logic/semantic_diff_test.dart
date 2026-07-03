import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

void main() {
  HttpRequestConfigEntity cfg({
    String method = 'GET',
    String url = 'https://api.dev',
    Map<String, String> headers = const {},
    String body = '',
    Map<String, String> auth = const {},
  }) => HttpRequestConfigEntity(
    id: 'c',
    method: method,
    url: url,
    headers: headers,
    body: body,
    auth: auth,
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
  });

  group('FolderNodeDiff', () {
    CollectionNodeEntity folder({
      String name = 'F',
      Map<String, String> variables = const {},
      List<CollectionNodeEntity> children = const [],
    }) => CollectionNodeEntity(
      id: 'f',
      name: name,
      isFolder: true,
      children: children,
      variables: variables,
    );

    test('name change reported', () {
      final d = FolderNodeDiff.diff(folder(), folder(name: 'G'));
      final n = d.changes.firstWhere((c) => c.field == 'name');
      expect(n.before, 'F');
      expect(n.after, 'G');
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

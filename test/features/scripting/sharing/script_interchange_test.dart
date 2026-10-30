import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/core/utils/code_gen_service.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/domain/logic/three_way_merge.dart';

CollectionNodeEntity leaf(RequestScripts scripts) => CollectionNodeEntity(
  id: 'r',
  name: 'Request',
  isFolder: false,
  config: HttpRequestConfigEntity(id: 'r', scripts: scripts),
);

void main() {
  const scripts = RequestScripts(
    apiVersion: 99,
    preRequest: 'α\nthrow "never";',
    postResponse: 'gm.test("ok");',
    preRequestEnabled: false,
  );
  test(
    'workspace roundtrips sources and unknown version without runtime state',
    () {
      final json = WorkspaceCollectionSerializer.requestToJson(leaf(scripts));
      final request = json['request'] as Map<String, dynamic>;
      expect(request['scripts'], isA<Map<String, dynamic>>());
      final bundle = request['scripts'] as Map<String, dynamic>;
      expect(bundle.keys.toSet(), {
        'apiVersion',
        'preRequest',
        'postResponse',
        'preRequestEnabled',
        'postResponseEnabled',
      });
      bundle.addAll({
        'trusted': true,
        'scriptLogs': ['forged'],
      });
      final restored = WorkspaceCollectionSerializer.requestFromJson(json);
      expect(restored.config!.scripts, scripts);
      expect(
        jsonEncode(WorkspaceCollectionSerializer.requestToJson(restored)),
        isNot(contains('trusted')),
      );
      expect(
        (WorkspaceCollectionSerializer.requestToJson(
                  leaf(const RequestScripts()),
                )['request']
                as Map)
            .containsKey('scripts'),
        isFalse,
      );
    },
  );
  test('Postman extension roundtrips without executable events', () {
    final json = PostmanCollectionMapper.toJson(leaf(scripts));
    expect(json, contains('x-getman-scripts'));
    expect(jsonDecode(json), isNot(contains('event')));
    expect(
      PostmanCollectionMapper.fromJson(json).children.single.config!.scripts,
      scripts,
    );
  });
  for (final level in ['root', 'folder', 'request']) {
    test('rejects Postman events at $level before producing a collection', () {
      final request = <String, dynamic>{
        'name': 'Request',
        'request': {'url': 'https://example.com'},
      };
      final folder = <String, dynamic>{
        'name': 'Folder',
        'item': [request],
      };
      final json = <String, dynamic>{
        'info': {'name': 'Collection', 'schema': 'v2.1'},
        'item': [folder],
      };
      (switch (level) {
        'root' => json,
        'folder' => folder,
        _ => request,
      })['event'] = [
        {
          'listen': 'test',
          'script': {
            'exec': ['throw 1'],
          },
        },
      ];
      expect(
        () => PostmanCollectionMapper.fromJson(jsonEncode(json)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'diagnostic',
            allOf(
              contains('Postman scripts are not supported'),
              contains(
                level == 'root'
                    ? 'Collection'
                    : level == 'folder'
                    ? 'Folder'
                    : 'Request',
              ),
            ),
          ),
        ),
      );
    });
  }
  test('independent stages merge and same-stage changes conflict', () {
    const base = RequestScripts(preRequest: 'base', postResponse: 'base');
    final incoming = base.copyWith(preRequest: 'incoming');
    final yours = base.copyWith(
      postResponse: 'yours',
      preRequestEnabled: false,
    );
    final merged = ThreeWayMerge.mergeRequest(
      leaf(base),
      leaf(incoming),
      leaf(yours),
    );
    expect(merged.conflicts, isEmpty);
    expect(
      merged.merged.config!.scripts,
      incoming.copyWith(postResponse: 'yours', preRequestEnabled: false),
    );
    final conflict = ThreeWayMerge.mergeRequest(
      leaf(base),
      leaf(incoming),
      leaf(base.copyWith(preRequest: 'yours')),
    );
    expect(conflict.conflicts.single.field, 'scripts.preRequest');
    expect(conflict.merged.config!.scripts.preRequest, 'incoming');
    expect(
      RequestConfigDiff.diff(
        leaf(base).config,
        leaf(incoming).config,
      ).changes.single.field,
      'scripts.preRequest',
    );
  });
  test('API docs warn that scripts are omitted', () {
    expect(
      CollectionToApiDoc.build(leaf(scripts)).warnings,
      contains(CodeGenService.scriptsOmittedWarning),
    );
  });
  test('code generation never includes or evaluates scripts', () {
    for (final target in CodeGenTarget.values) {
      final code = CodeGenService.generate(leaf(scripts).config!, target);
      expect(code, contains('Scripts are not included in generated code'));
      expect(code, isNot(contains('throw "never"')));
    }
  });
}

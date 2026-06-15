import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';

void main() {
  group('CollectionNode <-> entity', () {
    test('round-trips the description (incl. nested children)', () {
      const entity = CollectionNodeEntity(
        id: 'root',
        name: 'Root',
        description: 'top-level notes',
        children: [
          CollectionNodeEntity(
            id: 'child',
            name: 'Child',
            isFolder: false,
            description: 'child notes',
          ),
        ],
      );

      final back = CollectionNode.fromEntity(entity).toEntity();

      expect(back.description, 'top-level notes');
      expect(back.children.single.description, 'child notes');
    });

    test('a null description round-trips as null', () {
      const entity = CollectionNodeEntity(id: 'a', name: 'A');
      final back = CollectionNode.fromEntity(entity).toEntity();
      expect(back.description, isNull);
    });

    test('round-trips saved examples incl. the response snapshot', () {
      final entity = CollectionNodeEntity(
        id: 'req',
        name: 'GetUsers',
        isFolder: false,
        config: const HttpRequestConfigEntity(
          id: 'req',
          url: 'https://api/users',
        ),
        examples: [
          SavedExampleEntity(
            id: 'e1',
            name: '200 OK',
            capturedAt: DateTime.utc(2026, 6, 14, 14, 32),
            config: const HttpRequestConfigEntity(
              id: 'req',
              url: 'https://api/users',
              statusCode: 200,
              responseBody: '{"ok":true}',
              responseHeaders: {'content-type': 'application/json'},
              durationMs: 42,
            ),
          ),
        ],
      );

      final back = CollectionNode.fromEntity(entity).toEntity();

      expect(back.examples, hasLength(1));
      final example = back.examples.single;
      expect(example.id, 'e1');
      expect(example.name, '200 OK');
      expect(example.capturedAt, DateTime.utc(2026, 6, 14, 14, 32));
      expect(example.config.statusCode, 200);
      expect(example.config.responseBody, '{"ok":true}');
      expect(example.config.responseHeaders, {
        'content-type': 'application/json',
      });
      expect(example.config.durationMs, 42);
    });

    test('a node with no examples round-trips as an empty list', () {
      const entity = CollectionNodeEntity(id: 'a', name: 'A');
      final back = CollectionNode.fromEntity(entity).toEntity();
      expect(back.examples, isEmpty);
    });

    test('an over-limit example response body is capped on disk', () {
      final hugeBody = 'x' * (kMaxPersistedResponseBodyChars + 1);
      final entity = CollectionNodeEntity(
        id: 'req',
        name: 'Big',
        isFolder: false,
        examples: [
          SavedExampleEntity(
            id: 'e1',
            name: 'huge',
            capturedAt: DateTime.utc(2026, 6, 14),
            config: HttpRequestConfigEntity(
              id: 'req',
              statusCode: 200,
              responseBody: hugeBody,
            ),
          ),
        ],
      );

      final back = CollectionNode.fromEntity(entity).toEntity();
      final cfg = back.examples.single.config;
      expect(cfg.responseBody, kResponseBodyTooLargePlaceholder);
      // Status/other fields survive; only the oversized body is dropped.
      expect(cfg.statusCode, 200);
    });

    test('a within-limit example body is kept verbatim', () {
      final entity = CollectionNodeEntity(
        id: 'req',
        name: 'Small',
        isFolder: false,
        examples: [
          SavedExampleEntity(
            id: 'e1',
            name: 'ok',
            capturedAt: DateTime.utc(2026, 6, 14),
            config: const HttpRequestConfigEntity(
              id: 'req',
              responseBody: '{"ok":true}',
            ),
          ),
        ],
      );
      final back = CollectionNode.fromEntity(entity).toEntity();
      expect(back.examples.single.config.responseBody, '{"ok":true}');
    });
  });

  group('CollectionNodeEntity.copyWith', () {
    test('preserves description when not provided', () {
      const node = CollectionNodeEntity(
        id: 'a',
        name: 'A',
        description: 'keep',
      );
      expect(node.copyWith(name: 'B').description, 'keep');
    });

    test('updates description when provided (incl. empty to clear)', () {
      const node = CollectionNodeEntity(id: 'a', name: 'A', description: 'old');
      expect(node.copyWith(description: 'new').description, 'new');
      expect(node.copyWith(description: '').description, '');
    });

    test('equality reflects the description', () {
      const a = CollectionNodeEntity(id: 'a', name: 'A', description: 'x');
      const b = CollectionNodeEntity(id: 'a', name: 'A', description: 'y');
      expect(a == b, isFalse);
    });
  });
}

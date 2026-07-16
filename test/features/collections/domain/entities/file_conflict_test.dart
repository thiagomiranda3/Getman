import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';
import 'package:getman/features/collections/domain/logic/three_way_merge.dart';

void main() {
  group('FileConflict', () {
    test('equal by path + kind, ignoring node identity', () {
      const a = FileConflict(path: 'a.json', kind: ConflictKind.request);
      const b = FileConflict(path: 'a.json', kind: ConflictKind.request);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing path makes instances unequal', () {
      const a = FileConflict(path: 'a.json', kind: ConflictKind.request);
      const b = FileConflict(path: 'b.json', kind: ConflictKind.request);

      expect(a, isNot(equals(b)));
    });

    test('differing kind makes instances unequal', () {
      const a = FileConflict(path: 'a.json', kind: ConflictKind.request);
      const b = FileConflict(path: 'a.json', kind: ConflictKind.folder);

      expect(a, isNot(equals(b)));
    });

    test('isFieldLevel is true when node is present', () {
      const withNode = FileConflict(
        path: 'a.json',
        kind: ConflictKind.request,
        node: NodeMergeResult(
          merged: CollectionNodeEntity(id: 'r1', name: 'Req'),
          conflicts: [],
        ),
      );
      const withoutNode = FileConflict(
        path: 'a.json',
        kind: ConflictKind.addAdd,
      );

      expect(withNode.isFieldLevel, isTrue);
      expect(withoutNode.isFieldLevel, isFalse);
    });
  });

  group('FileResolution', () {
    test('equal when path, fieldChoices, and wholeFile all match', () {
      const a = FileResolution(
        path: 'a.json',
        fieldChoices: {'url': 'https://a'},
        wholeFile: FileSide.incoming,
      );
      const b = FileResolution(
        path: 'a.json',
        fieldChoices: {'url': 'https://a'},
        wholeFile: FileSide.incoming,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing wholeFile makes instances unequal', () {
      const a = FileResolution(
        path: 'a.json',
        fieldChoices: {'url': 'https://a'},
        wholeFile: FileSide.incoming,
      );
      const b = FileResolution(
        path: 'a.json',
        fieldChoices: {'url': 'https://a'},
        wholeFile: FileSide.yours,
      );

      expect(a, isNot(equals(b)));
    });

    test('differing fieldChoices makes instances unequal', () {
      const a = FileResolution(
        path: 'a.json',
        fieldChoices: {'url': 'https://a'},
      );
      const b = FileResolution(
        path: 'a.json',
        fieldChoices: {'url': 'https://b'},
      );

      expect(a, isNot(equals(b)));
    });

    test('defaults are empty fieldChoices and null wholeFile', () {
      const a = FileResolution(path: 'a.json');

      expect(a.fieldChoices, isEmpty);
      expect(a.wholeFile, isNull);
    });
  });
}

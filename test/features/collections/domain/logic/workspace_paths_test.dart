import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/domain/logic/workspace_paths.dart';

void main() {
  group('isWorkspacePath', () {
    test('accepts the workspace manifest', () {
      expect(isWorkspacePath('.getman/workspace.json'), isTrue);
    });

    test('accepts folder metas at any depth, including the root', () {
      expect(isWorkspacePath('a/.folder.json'), isTrue);
      expect(isWorkspacePath('.folder.json'), isTrue);
    });

    test('accepts request files at any depth', () {
      expect(isWorkspacePath('x.req.json'), isTrue);
      expect(isWorkspacePath('sub/dir/y.req.json'), isTrue);
    });

    test('rejects files the workspace mirror does not own', () {
      expect(isWorkspacePath('.DS_Store'), isFalse);
      expect(isWorkspacePath('README.md'), isFalse);
    });

    test(
      'rejects a file merely ending in ".folder.json" — folder metas are '
      'exactly "/.folder.json"',
      () {
        expect(isWorkspacePath('foo.folder.json'), isFalse);
      },
    );
  });
}

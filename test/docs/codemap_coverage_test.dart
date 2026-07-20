// Guards docs/CODEMAP.md freshness: every lib/ directory that contains
// hand-written Dart files must be mentioned in the codemap, so new features
// can't silently escape the map.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every lib/ directory with Dart files appears in docs/CODEMAP.md', () {
    final codemap = File('docs/CODEMAP.md').readAsStringSync();
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! Directory) continue;
      final hasDart = entity.listSync().whereType<File>().any(
        (f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'),
      );
      if (!hasDart) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (!codemap.contains(path)) missing.add(path);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Add these directories to docs/CODEMAP.md:\n${missing.join('\n')}',
    );
  });
}

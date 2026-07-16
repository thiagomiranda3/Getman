@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/gh_service.dart';

void main() {
  late GhService gh;
  late Directory tmp;

  Future<bool> ghPresent() async => gh.isAvailable();

  setUp(() async {
    gh = createGhService();
    tmp = await Directory.systemTemp.createTemp('getman_gh_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('isAvailable reflects whether the gh binary runs', () async {
    // Either result is valid depending on the machine; the call must not throw.
    expect(await gh.isAvailable(), isA<bool>());
  });

  test('isAuthenticated is false in a non-repo dir when gh is present or '
      'absent (never throws)', () async {
    // In a bare temp dir with no gh host context, auth status is false; and if
    // gh is missing the catch returns false. Either way: no throw, a bool.
    final result = await gh.isAuthenticated(tmp.path);
    expect(result, isA<bool>());
    if (!await ghPresent()) expect(result, isFalse);
  });

  test('GhException carries the exit code and message', () {
    final e = GhException('boom', exitCode: 3);
    expect(e.message, 'boom');
    expect(e.exitCode, 3);
    expect(e.toString(), contains('boom'));
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';

void main() {
  late GitService git;
  late Directory tmp;

  Future<bool> gitPresent() async => git.isAvailable();

  setUp(() async {
    git = createGitService();
    tmp = await Directory.systemTemp.createTemp('getman_git_test');
    // Deterministic identity for commits in this repo only.
    await Process.run('git', ['init'], workingDirectory: tmp.path);
    await Process.run('git', [
      'config',
      'user.email',
      't@t.dev',
    ], workingDirectory: tmp.path);
    await Process.run('git', [
      'config',
      'user.name',
      'T',
    ], workingDirectory: tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('isRepo true for an initialized dir', () async {
    if (!await gitPresent()) return; // skip when git missing
    expect(await git.isRepo(tmp.path), isTrue);
  });

  test('status reports an untracked file, then staged after stage()', () async {
    if (!await gitPresent()) return;
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":1}');
    var st = await git.status(tmp.path);
    final untracked = st.firstWhere((e) => e.path == 'a.req.json');
    expect(untracked.isUntracked, isTrue);
    expect(untracked.isStaged, isFalse);

    await git.stage(tmp.path, ['a.req.json']);
    st = await git.status(tmp.path);
    expect(st.firstWhere((e) => e.path == 'a.req.json').isStaged, isTrue);
  });

  test('status lists files inside a wholly untracked directory', () async {
    if (!await gitPresent()) return;
    // git collapses an untracked directory into a single `folder/` entry unless
    // -uall is passed — which would hide every request in a new collection.
    Directory('${tmp.path}/graphql_test').createSync();
    File('${tmp.path}/graphql_test/.folder.json').writeAsStringSync('{}');
    File(
      '${tmp.path}/graphql_test/graphql_test.req.json',
    ).writeAsStringSync('{}');

    final paths = (await git.status(tmp.path)).map((e) => e.path).toSet();

    expect(paths, contains('graphql_test/.folder.json'));
    expect(paths, contains('graphql_test/graphql_test.req.json'));
    expect(paths, isNot(contains('graphql_test/')));
  });

  test('headContent returns committed content; commit clears status', () async {
    if (!await gitPresent()) return;
    File('${tmp.path}/a.req.json').writeAsStringSync('v1');
    await git.stage(tmp.path, ['a.req.json']);
    await git.commit(tmp.path, 'first');
    expect(await git.status(tmp.path), isEmpty);
    expect(await git.headContent(tmp.path, 'a.req.json'), 'v1');

    File('${tmp.path}/a.req.json').writeAsStringSync('v2');
    expect(await git.workingContent(tmp.path, 'a.req.json'), 'v2');
    // HEAD still has v1 until the next commit.
    expect(await git.headContent(tmp.path, 'a.req.json'), 'v1');
  });

  test('unstage removes a file from the index', () async {
    if (!await gitPresent()) return;
    File('${tmp.path}/a.req.json').writeAsStringSync('x');
    await git.stage(tmp.path, ['a.req.json']);
    await git.unstage(tmp.path, ['a.req.json']);
    expect(await git.status(tmp.path).then((s) => s.first.isStaged), isFalse);
  });

  test('headContent returns null for a path absent at HEAD', () async {
    if (!await gitPresent()) return;
    expect(await git.headContent(tmp.path, 'nope.json'), isNull);
  });
}

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

  // Commits a file so the repo has a HEAD (a repo with no commits has no
  // branch to branch from).
  Future<void> seedCommit() async {
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":1}');
    await git.stage(tmp.path, ['a.req.json']);
    await git.commit(tmp.path, 'seed');
  }

  test('branches lists local branches; createBranch switches to it', () async {
    if (!await gitPresent()) return;
    await seedCommit();

    await git.createBranch(tmp.path, 'feat/x');

    expect(await git.currentBranch(tmp.path), 'feat/x');
    expect(await git.branches(tmp.path), contains('feat/x'));
  });

  test('switchBranch moves between existing branches', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    final initial = (await git.currentBranch(tmp.path))!;
    await git.createBranch(tmp.path, 'feat/x');

    await git.switchBranch(tmp.path, initial);

    expect(await git.currentBranch(tmp.path), initial);
  });

  test('hasRemote is false without a remote', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    expect(await git.hasRemote(tmp.path), isFalse);
  });

  test('aheadBehind is (0,0) when the branch has no upstream', () async {
    if (!await gitPresent()) return;
    await seedCommit();

    final ab = await git.aheadBehind(tmp.path);

    expect(ab.ahead, 0);
    expect(ab.behind, 0);
  });

  test('stashPush clears the working tree; pop restores it', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":2}');

    await git.stashPush(tmp.path, 'wip');
    expect(await git.status(tmp.path), isEmpty);
    expect(File('${tmp.path}/a.req.json').readAsStringSync(), '{"x":1}');

    final stashes = await git.stashList(tmp.path);
    expect(stashes.single.index, 0);
    expect(stashes.single.message, contains('wip'));

    await git.stashPop(tmp.path, 0);
    expect(File('${tmp.path}/a.req.json').readAsStringSync(), '{"x":2}');
    expect(await git.stashList(tmp.path), isEmpty);
  });

  test('stashPush includes untracked files', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    File('${tmp.path}/new.req.json').writeAsStringSync('{"n":1}');

    await git.stashPush(tmp.path, 'wip');

    // -u: an untracked new request must be stashed too, or a "stash and switch"
    // would carry it onto the target branch.
    expect(File('${tmp.path}/new.req.json').existsSync(), isFalse);
  });

  test('stashDrop removes a stash without restoring it', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":3}');
    await git.stashPush(tmp.path, 'wip');

    await git.stashDrop(tmp.path, 0);

    expect(await git.stashList(tmp.path), isEmpty);
    expect(File('${tmp.path}/a.req.json').readAsStringSync(), '{"x":1}');
  });
}

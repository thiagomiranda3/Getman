@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';

void main() {
  late GitService git;
  late Directory remote; // bare repo standing in for origin — no network
  late Directory a; // clone A (the "app")
  late Directory b; // clone B (a teammate)

  Future<void> run(String dir, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
    }
  }

  Future<void> identify(String dir) async {
    await run(dir, ['config', 'user.email', 't@t.dev']);
    await run(dir, ['config', 'user.name', 'T']);
  }

  Future<void> commitFile(String dir, String name, String content) async {
    File('$dir/$name').writeAsStringSync(content);
    await run(dir, ['add', '--', name]);
    await run(dir, ['commit', '-m', 'change $name']);
  }

  Future<bool> gitPresent() async => git.isAvailable();

  setUp(() async {
    git = createGitService();
    remote = await Directory.systemTemp.createTemp('getman_remote');
    a = await Directory.systemTemp.createTemp('getman_a');
    b = await Directory.systemTemp.createTemp('getman_b');
    if (!await gitPresent()) return;

    await run(remote.path, ['init', '--bare', '--initial-branch=main']);

    // Seed clone A and publish an initial commit.
    await run(a.path, ['init', '--initial-branch=main']);
    await identify(a.path);
    await run(a.path, ['remote', 'add', 'origin', remote.path]);
    await commitFile(a.path, 'a.req.json', '{"v":1}');
    await run(a.path, ['push', '-u', 'origin', 'main']);

    // Clone B from the same bare repo.
    await run(b.path, ['clone', remote.path, '.']);
    await identify(b.path);
  });

  tearDown(() async {
    for (final d in [remote, a, b]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  test('hasRemote is true for a cloned repo', () async {
    if (!await gitPresent()) return;
    expect(await git.hasRemote(a.path), isTrue);
  });

  test('push publishes local commits; the remote advances', () async {
    if (!await gitPresent()) return;
    await commitFile(a.path, 'b.req.json', '{"v":2}');
    expect((await git.aheadBehind(a.path)).ahead, 1);

    await git.push(a.path, setUpstream: false);

    expect((await git.aheadBehind(a.path)).ahead, 0);
  });

  test('push with setUpstream publishes a brand-new branch', () async {
    if (!await gitPresent()) return;
    await git.createBranch(a.path, 'feat/x');
    await commitFile(a.path, 'c.req.json', '{"v":3}');
    expect(await git.hasUpstream(a.path), isFalse);

    await git.push(a.path, setUpstream: true);

    expect(await git.hasUpstream(a.path), isTrue);
  });

  test('pull rebases the teammate commit into the local branch', () async {
    if (!await gitPresent()) return;
    // Teammate publishes a change.
    await commitFile(b.path, 'teammate.req.json', '{"v":9}');
    await run(b.path, ['push', 'origin', 'main']);
    await run(a.path, ['fetch', 'origin']);

    await git.pull(a.path);

    expect(File('${a.path}/teammate.req.json').existsSync(), isTrue);
  });

  test('a conflicting pull aborts and leaves the tree untouched', () async {
    if (!await gitPresent()) return;
    // Both sides edit the same file differently.
    await commitFile(b.path, 'a.req.json', '{"v":"theirs"}');
    await run(b.path, ['push', 'origin', 'main']);
    await commitFile(a.path, 'a.req.json', '{"v":"mine"}');

    await expectLater(
      git.pull(a.path),
      throwsA(isA<GitException>()),
    );

    // The abort must restore the pre-pull state exactly: our content is
    // intact, no conflict markers, no rebase in progress, and the tree is
    // clean.
    expect(File('${a.path}/a.req.json').readAsStringSync(), '{"v":"mine"}');
    expect(await git.status(a.path), isEmpty);
    expect(Directory('${a.path}/.git/rebase-merge').existsSync(), isFalse);
    expect(Directory('${a.path}/.git/rebase-apply').existsSync(), isFalse);
  });

  test(
    'aheadBehind reports ahead and behind against a real upstream',
    () async {
      if (!await gitPresent()) return;
      // Teammate publishes 2 commits; we make 1 locally and do not push.
      await commitFile(b.path, 'x.req.json', '{"v":1}');
      await commitFile(b.path, 'y.req.json', '{"v":2}');
      await run(b.path, ['push', 'origin', 'main']);
      await commitFile(a.path, 'mine.req.json', '{"v":3}');
      await run(a.path, ['fetch', 'origin']);

      final ab = await git.aheadBehind(a.path);

      // Asymmetric counts on purpose: a swapped mapping would pass a 1/1 test.
      expect(ab.ahead, 1);
      expect(ab.behind, 2);
    },
  );
}

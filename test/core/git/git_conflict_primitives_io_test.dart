@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';

void main() {
  late GitService git;
  late Directory tmp;

  Future<bool> gitPresent() async => git.isAvailable();
  Future<void> run(String dir, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir);
    if (r.exitCode != 0) throw Exception('git ${args.join(' ')}: ${r.stderr}');
  }

  Future<String> setUpConflictedRebase() async {
    final root = tmp.path;
    await run(root, ['init', '-b', 'main']);
    await run(root, ['config', 'user.email', 't@t.co']);
    await run(root, ['config', 'user.name', 't']);
    final f = File('$root/a.req.json')..writeAsStringSync('{"v":0}\n');
    await run(root, ['add', '.']);
    await run(root, ['commit', '-m', 'base']);
    // upstream commit
    f.writeAsStringSync('{"v":1}\n');
    await run(root, ['commit', '-am', 'upstream']);
    await run(root, ['branch', 'feature', 'HEAD~1']);
    await run(root, ['switch', 'feature']);
    f.writeAsStringSync('{"v":2}\n');
    await run(root, ['commit', '-am', 'yours']);
    // rebase feature onto main -> conflict
    final r = await Process.run('git', [
      'rebase',
      'main',
    ], workingDirectory: root);
    expect(r.exitCode, isNot(0));
    return root;
  }

  setUp(() async {
    git = createGitService();
    tmp = await Directory.systemTemp.createTemp('getman_conflict');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test(
    'a conflicting rebase exposes stages, resolves, and continues',
    () async {
      if (!await gitPresent()) return; // skip when git is absent
      final root = await setUpConflictedRebase();

      expect(await git.isRebaseInProgress(root), isTrue);
      expect(await git.conflictedPaths(root), contains('a.req.json'));
      expect(await git.showStage(root, 'a.req.json', 1), contains('"v":0'));
      expect(
        await git.showStage(root, 'a.req.json', 2),
        contains('"v":1'),
      ); // incoming (main)
      expect(
        await git.showStage(root, 'a.req.json', 3),
        contains('"v":2'),
      ); // yours

      await git.writeWorkingFile(root, 'a.req.json', '{"v":9}\n');
      await git.add(root, 'a.req.json');
      await git.rebaseContinue(root);
      expect(await git.isRebaseInProgress(root), isFalse);
      expect(File('$root/a.req.json').readAsStringSync(), contains('"v":9'));
    },
  );

  test('rebaseAbort restores the pre-rebase tree', () async {
    if (!await gitPresent()) return;
    final root = await setUpConflictedRebase();
    expect(await git.isRebaseInProgress(root), isTrue);

    await git.rebaseAbort(root);

    expect(await git.isRebaseInProgress(root), isFalse);
    // Back on `feature`, at the pre-rebase content (not the conflict markers).
    expect(await git.currentBranch(root), 'feature');
    expect(File('$root/a.req.json').readAsStringSync(), contains('"v":2'));
    expect(await git.conflictedPaths(root), isEmpty);
  });
}

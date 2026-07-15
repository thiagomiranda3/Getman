@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';

/// Real-git coverage for the Getman-owned commit identity: a `commit`
/// creating a commit succeeds even when the repo has no local *or* global
/// git identity configured, as long as [GitService.commit] is given one
/// inline — and, conversely, a commit attempted with none at all fails with
/// [GitException.isMissingIdentity].
///
/// Deliberately does **not** run `git config user.name/user.email` in
/// [setUp] (unlike `git_service_io_test.dart`'s shared fixture) — the whole
/// point is a repo with no identity of its own.
void main() {
  late GitService git;
  late Directory tmp;

  Future<bool> gitPresent() async => git.isAvailable();

  setUp(() async {
    git = createGitService();
    tmp = await Directory.systemTemp.createTemp('getman_git_identity_test');
    await Process.run('git', ['init'], workingDirectory: tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test(
    'commit with an inline identity succeeds and authors as that identity',
    () async {
      if (!await gitPresent()) return; // skip when git missing
      File('${tmp.path}/a.req.json').writeAsStringSync('{"x":1}');
      await git.stage(tmp.path, ['a.req.json']);

      await git.commit(
        tmp.path,
        'seed',
        authorName: 'A Getman User',
        authorEmail: 'a.getman.user@example.com',
      );

      final log = await Process.run('git', [
        'log',
        '-1',
        '--format=%an <%ae>',
      ], workingDirectory: tmp.path);
      expect(
        (log.stdout as String).trim(),
        'A Getman User <a.getman.user@example.com>',
      );
    },
  );

  test(
    'commit with no identity at all (repo and inline both absent) throws a '
    'GitException whose message is detected as a missing identity',
    () async {
      if (!await gitPresent()) return; // skip when git missing
      File('${tmp.path}/a.req.json').writeAsStringSync('{"x":1}');
      await git.stage(tmp.path, ['a.req.json']);

      await expectLater(
        git.commit(tmp.path, 'seed'),
        throwsA(
          isA<GitException>().having(
            (e) => GitException.isMissingIdentity(e.message),
            'isMissingIdentity',
            isTrue,
          ),
        ),
      );
    },
  );
}

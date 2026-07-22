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
/// point is a repo with no identity of its own. The service is built with
/// `GIT_CONFIG_GLOBAL` pointed at an isolated file (+ `GIT_CONFIG_NOSYSTEM`)
/// so the developer machine's real `~/.gitconfig` identity can't leak in and
/// make the missing-identity commits silently succeed. That file sets
/// `user.useConfigOnly = true`, which disables git's own fallback of
/// guessing an identity from the OS account/hostname (real on a normal
/// desktop account — `git commit` there just warns and succeeds instead of
/// failing) — without it this test is flaky/environment-dependent instead of
/// deterministic.
void main() {
  late GitService git;
  late Directory tmp;

  Future<bool> gitPresent() async => git.isAvailable();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('getman_git_identity_test');
    final isolatedGlobalConfig = File('${tmp.path}/empty-gitconfig')
      ..writeAsStringSync('[user]\n\tuseConfigOnly = true\n');
    git = createGitService(
      environmentOverrides: {
        'GIT_CONFIG_GLOBAL': isolatedGlobalConfig.path,
        'GIT_CONFIG_NOSYSTEM': '1',
      },
    );
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
      // The name carries the " via Getman" attribution suffix (applied only at
      // commit time); the email is verbatim so GitHub still credits the user.
      expect(
        (log.stdout as String).trim(),
        'A Getman User via Getman <a.getman.user@example.com>',
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

  test(
    'commit with only a partial inline identity (name without email, or '
    'vice versa) is treated as no identity and throws a GitException '
    'detected as a missing identity',
    () async {
      if (!await gitPresent()) return; // skip when git missing
      File('${tmp.path}/a.req.json').writeAsStringSync('{"x":1}');
      await git.stage(tmp.path, ['a.req.json']);

      // Name without email: _identityArgs must produce no -c args at all
      // (not a garbage user.email=), so git falls back to its own
      // resolution and fails the same way as with no identity.
      await expectLater(
        git.commit(tmp.path, 'seed', authorName: 'X'),
        throwsA(
          isA<GitException>().having(
            (e) => GitException.isMissingIdentity(e.message),
            'isMissingIdentity',
            isTrue,
          ),
        ),
      );

      // Email without name: same expectation, reversed.
      await expectLater(
        git.commit(tmp.path, 'seed', authorEmail: 'x@example.com'),
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

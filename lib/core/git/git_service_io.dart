import 'dart:convert';
import 'dart:io';

import 'package:getman/core/git/git_service.dart';

GitService createGitService() => _IoGitService();

class _IoGitService implements GitService {
  Future<ProcessResult> _run(
    String root,
    List<String> args, {
    bool allowFailure = false,
  }) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure && result.exitCode != 0) {
      throw GitException(
        (result.stderr as String).trim().isEmpty
            ? 'git ${args.first} failed'
            : (result.stderr as String).trim(),
        exitCode: result.exitCode,
      );
    }
    return result;
  }

  /// `-c user.name=… -c user.email=…`, prepended to the git args of any
  /// commit-creating command — never written to the user's global git
  /// config. Empty when either half is missing/blank so git falls back to
  /// its own resolution (and a genuinely missing identity still surfaces as
  /// [GitException.isMissingIdentity]).
  ///
  /// The stored name is suffixed with [_viaGetman] only at commit time (the
  /// setting stays clean), so history reads `name via Getman` while GitHub —
  /// which attributes by email — still credits the user normally.
  List<String> _identityArgs(String? name, String? email) =>
      (name != null && name.isNotEmpty && email != null && email.isNotEmpty)
      ? ['-c', 'user.name=$name$_viaGetman', '-c', 'user.email=$email']
      : const [];

  static const String _viaGetman = ' via Getman';

  @override
  Future<bool> isAvailable() async {
    try {
      final r = await Process.run('git', ['--version']);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isRepo(String root) async {
    if (!Directory(root).existsSync()) return false;
    final r = await _run(
      root,
      ['rev-parse', '--is-inside-work-tree'],
      allowFailure: true,
    );
    return r.exitCode == 0 && (r.stdout as String).trim() == 'true';
  }

  @override
  Future<void> init(String root) async {
    await Directory(root).create(recursive: true);
    await _run(root, ['init']);
  }

  @override
  Future<String?> currentBranch(String root) async {
    final r = await _run(root, [
      'branch',
      '--show-current',
    ], allowFailure: true);
    final name = (r.stdout as String).trim();
    return name.isEmpty ? null : name;
  }

  @override
  Future<List<GitStatusEntry>> status(String root) async {
    // `-uall` lists every untracked *file*. Without it git collapses a wholly
    // untracked directory into one `folder/` entry, so a brand-new collection
    // folder would hide its .folder.json and every request inside it.
    final r = await _run(root, ['status', '--porcelain=v1', '-z', '-uall']);
    return _parseStatusZ(r.stdout as String);
  }

  @override
  Future<String?> headContent(String root, String path) async {
    final r = await _run(root, ['show', 'HEAD:$path'], allowFailure: true);
    return r.exitCode == 0 ? r.stdout as String : null;
  }

  @override
  Future<String?> workingContent(String root, String path) async {
    final file = File('$root/$path');
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  @override
  Future<void> stage(String root, List<String> paths) async {
    if (paths.isEmpty) return;
    await _run(root, ['add', '--', ...paths]);
  }

  @override
  Future<void> unstage(String root, List<String> paths) async {
    if (paths.isEmpty) return;
    // `git reset` fails on a repo with no commits yet; fall back to
    // rm --cached.
    final r = await _run(
      root,
      ['reset', '-q', 'HEAD', '--', ...paths],
      allowFailure: true,
    );
    if (r.exitCode != 0) {
      await _run(root, [
        'rm',
        '--cached',
        '-q',
        '--',
        ...paths,
      ], allowFailure: true);
    }
  }

  @override
  Future<void> commit(
    String root,
    String message, {
    String? authorName,
    String? authorEmail,
  }) async {
    await _run(root, [
      ..._identityArgs(authorName, authorEmail),
      'commit',
      '-m',
      message,
    ]);
  }

  @override
  Future<List<String>> branches(String root) async {
    final r = await _run(root, [
      'branch',
      '--format=%(refname:short)',
    ]);
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Future<void> createBranch(String root, String name) async {
    await _run(root, ['switch', '-c', name]);
  }

  @override
  Future<void> switchBranch(String root, String name) async {
    await _run(root, ['switch', name]);
  }

  @override
  Future<bool> hasRemote(String root) async {
    final r = await _run(root, ['remote'], allowFailure: true);
    return (r.stdout as String).trim().isNotEmpty;
  }

  @override
  Future<AheadBehind> aheadBehind(String root) async {
    // `@{u}...HEAD` prints "<behind>\t<ahead>". Exits non-zero when the
    // branch has no upstream — that is a normal state, so report (0, 0).
    final r = await _run(root, [
      'rev-list',
      '--left-right',
      '--count',
      '@{u}...HEAD',
    ], allowFailure: true);
    if (r.exitCode != 0) return AheadBehind.none;
    final parts = (r.stdout as String).trim().split(RegExp(r'\s+'));
    if (parts.length != 2) return AheadBehind.none;
    return AheadBehind(
      behind: int.tryParse(parts[0]) ?? 0,
      ahead: int.tryParse(parts[1]) ?? 0,
    );
  }

  @override
  Future<bool> hasUpstream(String root) async {
    final r = await _run(root, [
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ], allowFailure: true);
    return r.exitCode == 0;
  }

  @override
  Future<PullOutcome> pull(
    String root, {
    String? authorName,
    String? authorEmail,
  }) async {
    final r = await _run(root, [
      ..._identityArgs(authorName, authorEmail),
      'pull',
      '--rebase',
    ], allowFailure: true);
    if (r.exitCode == 0) return PullOutcome.clean;
    if (await isRebaseInProgress(root) &&
        (await conflictedPaths(root)).isNotEmpty) {
      return PullOutcome.conflicted; // leave paused for the resolver
    }
    // Not a resolvable conflict (auth/network/local changes) — restore + throw.
    await _run(root, ['rebase', '--abort'], allowFailure: true);
    final err = (r.stderr as String).trim();
    throw GitException(
      err.isEmpty ? 'git pull failed' : err,
      exitCode: r.exitCode,
    );
  }

  @override
  Future<void> push(String root, {required bool setUpstream}) async {
    final branch = await currentBranch(root);
    if (branch == null) throw GitException('no current branch to push');
    await _run(root, [
      'push',
      if (setUpstream) '-u',
      if (setUpstream) 'origin',
      if (setUpstream) branch,
    ]);
  }

  @override
  Future<List<StashEntry>> stashList(String root) async {
    final r = await _run(root, ['stash', 'list', '--format=%gs']);
    final lines = (r.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return [
      for (var i = 0; i < lines.length; i++)
        StashEntry(index: i, message: lines[i].trim()),
    ];
  }

  @override
  Future<void> stashPush(String root, String message) async {
    await _run(root, ['stash', 'push', '-u', '-m', message]);
  }

  @override
  Future<void> stashPop(String root, int index) async {
    await _run(root, ['stash', 'pop', 'stash@{$index}']);
  }

  @override
  Future<void> stashDrop(String root, int index) async {
    await _run(root, ['stash', 'drop', 'stash@{$index}']);
  }

  @override
  Future<bool> isRebaseInProgress(String root) async {
    final r = await _run(root, [
      'rev-parse',
      '--git-path',
      'rebase-merge',
    ], allowFailure: true);
    final merge = (r.stdout as String).trim();
    if (merge.isNotEmpty && Directory('$root/$merge').existsSync()) return true;
    final r2 = await _run(root, [
      'rev-parse',
      '--git-path',
      'rebase-apply',
    ], allowFailure: true);
    final apply = (r2.stdout as String).trim();
    return apply.isNotEmpty && Directory('$root/$apply').existsSync();
  }

  @override
  Future<List<String>> conflictedPaths(String root) async {
    final r = await _run(root, ['diff', '--name-only', '--diff-filter=U']);
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Future<String?> showStage(String root, String path, int stage) async {
    final r = await _run(root, ['show', ':$stage:$path'], allowFailure: true);
    return r.exitCode == 0 ? r.stdout as String : null;
  }

  @override
  Future<void> writeWorkingFile(
    String root,
    String path,
    String content,
  ) async {
    final file = File('$root/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> add(String root, String path) => _run(root, ['add', path]);

  @override
  Future<void> removeFile(String root, String path) =>
      _run(root, ['rm', '--', path]);

  @override
  Future<void> rebaseContinue(
    String root, {
    String? authorName,
    String? authorEmail,
  }) async {
    // GIT_EDITOR=true so a commit-message step never blocks on an editor.
    final r = await Process.run(
      'git',
      [..._identityArgs(authorName, authorEmail), 'rebase', '--continue'],
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: {'GIT_EDITOR': 'true'},
    );
    if (r.exitCode != 0) {
      final err = (r.stderr as String).trim();
      throw GitException(
        err.isEmpty ? 'git rebase --continue failed' : err,
        exitCode: r.exitCode,
      );
    }
  }

  @override
  Future<void> rebaseAbort(String root) => _run(root, ['rebase', '--abort']);

  @override
  Future<void> fetch(String root) => _run(root, ['fetch']);

  /// Parses `git status --porcelain=v1 -z`. Records are NUL-terminated; a
  /// rename record (`R`/`C`) is followed by a second NUL-token holding the
  /// source path.
  static List<GitStatusEntry> _parseStatusZ(String raw) {
    final tokens = raw.split('\x00')..removeWhere((t) => t.isEmpty);
    final out = <GitStatusEntry>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.length < 4) continue;
      final index = token[0];
      final worktree = token[1];
      final path = token.substring(3);
      String? renamedFrom;
      if (index == 'R' || index == 'C') {
        if (i + 1 < tokens.length) renamedFrom = tokens[++i];
      }
      out.add(
        GitStatusEntry(
          indexStatus: index,
          worktreeStatus: worktree,
          path: path,
          renamedFrom: renamedFrom,
        ),
      );
    }
    return out;
  }
}

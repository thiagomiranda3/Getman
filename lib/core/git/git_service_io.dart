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
    final r = await _run(root, ['status', '--porcelain=v1', '-z']);
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
  Future<void> commit(String root, String message) async {
    await _run(root, ['commit', '-m', message]);
  }

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

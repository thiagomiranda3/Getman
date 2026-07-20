// dart:io implementation of GhService: shells out to the `gh` CLI via
// Process.run. Gotcha: Process.run closes the child's stdin (EOF), so `gh`
// runs non-interactively and errors instead of prompting — this upholds the
// "throws, never hangs" contract. Never switch to Process.start with an
// open stdin, and note there is no timeout, so a gh call blocked on
// something other than stdin would hang forever.
import 'dart:convert';
import 'dart:io';

import 'package:getman/core/git/gh_output_parser.dart';
import 'package:getman/core/git/gh_service.dart';

GhService createGhServiceImpl() => _GhService();

class _GhService implements GhService {
  // NOTE: `Process.run` closes the child's stdin (it gets EOF), so `gh` runs
  // non-interactively and errors instead of prompting — this is what upholds
  // the "throws, never hangs" contract. Two things must stay true: (1) never
  // switch to `Process.start` with an open stdin, and (2) there is no timeout,
  // so any gh call that could block on something *other* than stdin would hang.
  Future<ProcessResult> _run(
    String root,
    List<String> args, {
    bool allowFailure = false,
  }) async {
    final result = await Process.run(
      'gh',
      args,
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure && result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      throw GhException(
        err.isEmpty ? 'gh ${args.first} failed' : err,
        exitCode: result.exitCode,
      );
    }
    return result;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final r = await Process.run('gh', ['--version']);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isAuthenticated(String root) async {
    try {
      final r = await _run(root, ['auth', 'status'], allowFailure: true);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<String> createPr(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  }) async {
    final r = await _run(root, [
      'pr',
      'create',
      '--base',
      base,
      '--title',
      title,
      '--body',
      body,
      if (draft) '--draft',
    ]);
    final url = parsePrUrl(r.stdout as String);
    if (url.isEmpty) {
      throw GhException('gh pr create did not return a PR url');
    }
    return url;
  }

  @override
  Future<List<PullRequestInfo>> listPrs(String root) async {
    final r = await _run(root, [
      'pr',
      'list',
      '--state',
      'open',
      '--json',
      'number,title,state,url,isDraft,statusCheckRollup',
    ]);
    return parsePrList(r.stdout as String);
  }

  @override
  Future<String?> defaultBranch(String root) async {
    final r = await _run(root, [
      'repo',
      'view',
      '--json',
      'defaultBranchRef',
    ], allowFailure: true);
    if (r.exitCode != 0) return null;
    // Best-effort: a non-JSON / empty stdout must yield null, not throw.
    try {
      final decoded = jsonDecode(r.stdout as String);
      if (decoded is! Map) return null;
      final ref = decoded['defaultBranchRef'];
      if (ref is! Map) return null;
      return ref['name'] as String?;
    } on FormatException {
      return null;
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:getman/core/git/gh_output_parser.dart';
import 'package:getman/core/git/gh_service.dart';

GhService createGhServiceImpl() => _GhService();

class _GhService implements GhService {
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
    // Filled in Task 3.
    throw UnimplementedError();
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
    final decoded = jsonDecode(r.stdout as String);
    if (decoded is! Map) return null;
    final ref = decoded['defaultBranchRef'];
    if (ref is! Map) return null;
    return ref['name'] as String?;
  }
}

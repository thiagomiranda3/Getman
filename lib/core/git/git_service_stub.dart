import 'package:getman/core/git/git_service.dart';

GitService createGitService() => _StubGitService();

/// Web build: git is unavailable; every op is a no-op / reports unavailable.
class _StubGitService implements GitService {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> isRepo(String root) async => false;
  @override
  Future<void> init(String root) async {}
  @override
  Future<String?> currentBranch(String root) async => null;
  @override
  Future<List<GitStatusEntry>> status(String root) async => const [];
  @override
  Future<String?> headContent(String root, String path) async => null;
  @override
  Future<String?> workingContent(String root, String path) async => null;
  @override
  Future<void> stage(String root, List<String> paths) async {}
  @override
  Future<void> unstage(String root, List<String> paths) async {}
  @override
  Future<void> commit(String root, String message) async {}
  @override
  Future<List<String>> branches(String root) async => const [];
  @override
  Future<void> createBranch(String root, String name) async {}
  @override
  Future<void> switchBranch(String root, String name) async {}
  @override
  Future<bool> hasRemote(String root) async => false;
  @override
  Future<AheadBehind> aheadBehind(String root) async => AheadBehind.none;
}

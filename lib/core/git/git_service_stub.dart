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
  Future<void> commit(
    String root,
    String message, {
    String? authorName,
    String? authorEmail,
  }) async {}
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
  @override
  Future<bool> hasUpstream(String root) async => false;
  @override
  Future<PullOutcome> pull(
    String root, {
    String? authorName,
    String? authorEmail,
  }) async => PullOutcome.clean;
  @override
  Future<void> push(String root, {required bool setUpstream}) async {}
  @override
  Future<List<StashEntry>> stashList(String root) async => const [];
  @override
  Future<void> stashPush(String root, String message) async {}
  @override
  Future<void> stashPop(String root, int index) async {}
  @override
  Future<void> stashDrop(String root, int index) async {}
  @override
  Future<bool> isRebaseInProgress(String root) async => false;
  @override
  Future<List<String>> conflictedPaths(String root) async => const [];
  @override
  Future<String?> showStage(String root, String path, int stage) async => null;
  @override
  Future<void> writeWorkingFile(
    String root,
    String path,
    String content,
  ) async {}
  @override
  Future<void> add(String root, String path) async {}
  @override
  Future<void> removeFile(String root, String path) async {}
  @override
  Future<void> rebaseContinue(
    String root, {
    String? authorName,
    String? authorEmail,
  }) async {}
  @override
  Future<void> rebaseAbort(String root) async {}
  @override
  Future<void> fetch(String root) async {}
}

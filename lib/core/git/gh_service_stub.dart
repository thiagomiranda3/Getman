// Web build's GhService: `gh` is a desktop CLI, so every call is a no-op
// reporting unavailable/failure. Selected by gh_service.dart's conditional
// export when dart:io is absent.
import 'package:getman/core/git/gh_service.dart';

GhService createGhServiceImpl() => _StubGhService();

/// Web build: `gh` is a desktop binary, so every call is a no-op that reports
/// "not available".
class _StubGhService implements GhService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> isAuthenticated(String root) async => false;

  @override
  Future<String> createPr(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  }) async => throw GhException('gh is unavailable on web');

  @override
  Future<List<PullRequestInfo>> listPrs(String root) async => const [];

  @override
  Future<String?> defaultBranch(String root) async => null;
}

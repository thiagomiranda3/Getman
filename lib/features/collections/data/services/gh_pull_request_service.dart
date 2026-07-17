// GhPullRequestService: gh-CLI-backed PullRequestService — availability
// check, listing PRs, and creating one. Composes GhService with
// BranchService so the pre-create push reuses the flush-guarded push.
import 'package:getman/core/git/gh_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';

/// `gh`-backed [PullRequestService]. Composes [GhService] with the Spec B
/// [BranchService] so the pre-create push reuses the flush-guarded push (no
/// duplicated mirror-race handling — PR creation itself never touches the
/// working tree).
class GhPullRequestService implements PullRequestService {
  GhPullRequestService(this._gh, this._branch);

  final GhService _gh;
  final BranchService _branch;

  @override
  Future<GhAvailability> availability(String root) async {
    if (!await _gh.isAvailable()) return GhAvailability.notInstalled;
    if (!await _gh.isAuthenticated(root)) {
      return GhAvailability.notAuthenticated;
    }
    return GhAvailability.available;
  }

  @override
  Future<List<PullRequestEntity>> list(String root) async {
    final raw = await _gh.listPrs(root);
    return [for (final p in raw) _toEntity(p)];
  }

  @override
  Future<PullRequestRef> create(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  }) async {
    // Ensure the branch (and its latest commits) are on the remote first —
    // gh pr create would otherwise prompt for a remote on stdin, which a
    // non-interactive Process.run cannot answer. push sets upstream on the
    // first push.
    await _branch.push(root);
    final url = await _gh.createPr(
      root,
      base: base,
      title: title,
      body: body,
      draft: draft,
    );
    return PullRequestRef(number: _numberFromUrl(url), url: url);
  }

  @override
  Future<String?> defaultBase(String root) => _gh.defaultBranch(root);

  PullRequestEntity _toEntity(PullRequestInfo p) => PullRequestEntity(
    number: p.number,
    title: p.title,
    state: switch (p.state) {
      'MERGED' => PrState.merged,
      'CLOSED' => PrState.closed,
      _ => PrState.open,
    },
    url: p.url,
    isDraft: p.isDraft,
    checks: switch (p.checks) {
      'pending' => PrChecks.pending,
      'passing' => PrChecks.passing,
      'failing' => PrChecks.failing,
      _ => PrChecks.none,
    },
  );

  int _numberFromUrl(String url) {
    // Drop any ?query / #fragment before taking the trailing path segment so a
    // `.../pull/77?foo=bar` URL still yields 77.
    final path = url.split(RegExp('[?#]')).first;
    final last = path.split('/').where((s) => s.isNotEmpty).lastOrNull;
    return int.tryParse(last ?? '') ?? 0;
  }
}

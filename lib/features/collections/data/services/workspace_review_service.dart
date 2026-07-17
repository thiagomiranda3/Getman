import 'dart:convert';

import 'package:getman/core/git/git_service.dart';
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/domain/review_service.dart';

/// Composes [GitService] + the workspace serializer into a reviewable change
/// set. Pure of `dart:io` — all filesystem/git access goes through [GitService].
class WorkspaceReviewService implements ReviewService {
  WorkspaceReviewService(this._git, this._sync);
  final GitService _git;
  final WorkspaceSyncService _sync;

  static const String _metaDir = '.getman';
  static const String _manifest = 'workspace.json';
  static const String _folderMeta = '.folder.json';
  static const String _reqExt = '.req.json';

  /// Runs the pending Hive → disk mirror to completion before any op that
  /// reads or mutates the working tree — same gate as `GitBranchService`.
  /// Without it, opening Review within the mirror debounce and staging lets
  /// `git add` stage the pre-edit blob while the dialog shows the post-edit
  /// diff, and the commit records content that differs from what was
  /// reviewed.
  Future<void> _flushOrThrow() async {
    if (!await _sync.flushPending()) {
      throw GitException(
        'Could not write the workspace to disk — aborting so git does not '
        'run over a stale tree. Check the workspace folder is writable.',
      );
    }
  }

  @override
  Future<ReviewResult> review(String root) async {
    if (!await _git.isAvailable()) return ReviewResult.empty;
    await _flushOrThrow();
    if (!await _git.isRepo(root)) {
      return const ReviewResult(
        gitAvailable: true,
        repoExists: false,
        branch: null,
        entries: [],
      );
    }
    final branch = await _git.currentBranch(root);
    final status = await _git.status(root);
    final entries = <ReviewEntry>[];
    for (final s in status) {
      final entry = await _entryFor(root, s);
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return ReviewResult(
      gitAvailable: true,
      repoExists: true,
      branch: branch,
      entries: entries,
    );
  }

  @override
  Future<void> init(String root) => _git.init(root);
  @override
  Future<void> stage(String root, List<String> paths) async {
    await _flushOrThrow();
    await _git.stage(root, paths);
  }

  @override
  Future<void> unstage(String root, List<String> paths) =>
      _git.unstage(root, paths);
  @override
  Future<void> commit(
    String root,
    String message, {
    String? authorName,
    String? authorEmail,
  }) async {
    await _flushOrThrow();
    await _git.commit(
      root,
      message,
      authorName: authorName,
      authorEmail: authorEmail,
    );
  }

  Future<ReviewEntry?> _entryFor(String root, GitStatusEntry s) async {
    final path = s.path;
    final headRaw = await _git.headContent(root, path);
    final workRaw = await _git.workingContent(root, path);
    final changeType = workRaw == null
        ? ChangeType.deleted
        : headRaw == null
        ? ChangeType.added
        : ChangeType.modified;

    if (path == '$_metaDir/$_manifest') {
      return ReviewEntry(
        path: path,
        nodeKind: NodeKind.workspaceOrder,
        changeType: changeType,
        displayName: 'Workspace order',
        staged: s.isStaged,
        diff: const SemanticDiff([
          FieldChange(field: 'root order', kind: ChangeKind.changed),
        ]),
      );
    }

    if (path.endsWith('/$_folderMeta') || path == _folderMeta) {
      final before = _parseFolder(headRaw);
      final after = _parseFolder(workRaw);
      return ReviewEntry(
        path: path,
        nodeKind: NodeKind.folder,
        changeType: changeType,
        displayName: (after ?? before)?.name ?? 'Folder',
        staged: s.isStaged,
        diff: FolderNodeDiff.diff(before, after),
      );
    }

    if (path.endsWith(_reqExt)) {
      final before = _parseRequest(headRaw);
      final after = _parseRequest(workRaw);
      return ReviewEntry(
        path: path,
        nodeKind: NodeKind.request,
        changeType: changeType,
        displayName: (after ?? before)?.name ?? 'Request',
        staged: s.isStaged,
        diff: RequestConfigDiff.diff(before?.config, after?.config),
      );
    }
    return null; // non-workspace file — ignore
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  static CollectionNodeEntity? _parseRequest(String? raw) {
    final json = _decode(raw);
    if (json == null) return null;
    return WorkspaceCollectionSerializer.requestFromJson(json);
  }

  static CollectionNodeEntity? _parseFolder(String? raw) {
    final json = _decode(raw);
    if (json == null) return null;
    final childOrder = WorkspaceCollectionSerializer.childOrder(json);
    // Placeholder children exist only so FolderNodeDiff's
    // children.map((c) => c.name) can detect reordering from the
    // .folder.json childOrder slugs — name = slug is intentional.
    final children = [
      for (final slug in childOrder) CollectionNodeEntity(id: slug, name: slug),
    ];
    return WorkspaceCollectionSerializer.folderFromJson(json, children);
  }
}

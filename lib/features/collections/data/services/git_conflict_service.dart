import 'dart:convert';

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/domain/conflict_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';
import 'package:getman/features/collections/domain/logic/three_way_merge.dart';

/// Drives semantic conflict resolution over a paused `git pull --rebase`:
/// classifies each conflicted path ([currentConflicts]), field-level 3-way
/// merges request/folder JSON via [ThreeWayMerge], and writes the user's
/// picks back to the working tree ([resolve]). Pure orchestration over
/// [GitService] — no `dart:io` here.
class GitConflictService implements ConflictService {
  GitConflictService(this._git);
  final GitService _git;

  static const JsonEncoder _enc = JsonEncoder.withIndent('  ');

  @override
  Future<PullOutcome> pullOrConflict(String root) => _git.pull(root);

  @override
  Future<RebaseStep> continueRebase(String root) async {
    await _git.rebaseContinue(root);
    return await _git.isRebaseInProgress(root)
        ? RebaseStep.moreConflicts
        : RebaseStep.done;
  }

  @override
  Future<void> abort(String root) => _git.rebaseAbort(root);

  // Fetch never touches the working tree — it only updates remote-tracking
  // refs — so unlike pull/resolve there is nothing here to flush or suspend.
  @override
  Future<void> fetch(String root) => _git.fetch(root);

  @override
  Future<List<FileConflict>> currentConflicts(String root) async {
    final paths = await _git.conflictedPaths(root);
    return [for (final p in paths) await _classify(root, p)];
  }

  Future<FileConflict> _classify(String root, String path) async {
    if (path.endsWith('.req.json')) {
      final s1 = await _git.showStage(root, path, 1);
      final s2 = await _git.showStage(root, path, 2); // incoming
      final s3 = await _git.showStage(root, path, 3); // yours
      // delete/modify: one side stage missing.
      if (s2 == null || s3 == null) {
        return FileConflict(path: path, kind: ConflictKind.deleteModify);
      }
      final base = _leafOrNull(s1);
      final inc = _leafOrNull(s2);
      final you = _leafOrNull(s3);
      if (inc == null || you == null) {
        return FileConflict(path: path, kind: ConflictKind.structural);
      }
      final node = ThreeWayMerge.mergeRequest(base, inc, you);
      return FileConflict(
        path: path,
        kind: s1 == null ? ConflictKind.addAdd : ConflictKind.request,
        node: node,
      );
    }
    if (path.endsWith('.folder.json')) {
      final s1 = await _git.showStage(root, path, 1);
      final s2 = await _git.showStage(root, path, 2); // incoming
      final s3 = await _git.showStage(root, path, 3); // yours
      if (s2 == null || s3 == null) {
        return FileConflict(path: path, kind: ConflictKind.deleteModify);
      }
      final base = _folderOrNull(s1);
      final inc = _folderOrNull(s2);
      final you = _folderOrNull(s3);
      if (inc == null || you == null) {
        return FileConflict(path: path, kind: ConflictKind.structural);
      }
      final node = ThreeWayMerge.mergeFolder(
        base,
        _folderOrderOrEmpty(s1),
        inc,
        _folderOrderOrEmpty(s2),
        you,
        _folderOrderOrEmpty(s3),
      );
      return FileConflict(
        path: path,
        kind: s1 == null ? ConflictKind.addAdd : ConflictKind.folder,
        node: node,
      );
    }
    return FileConflict(path: path, kind: ConflictKind.structural);
  }

  @override
  Future<void> resolve(String root, List<FileResolution> resolutions) async {
    for (final res in resolutions) {
      if (res.wholeFile != null) {
        await _resolveWholeFile(root, res);
        continue;
      }
      final content = await _resolvedContent(root, res); // apply picks → JSON
      await _git.writeWorkingFile(root, res.path, content);
      await _git.add(root, res.path);
    }
  }

  /// Coarse resolutions pick a whole merge-stage side verbatim. When the
  /// chosen side is the deleting side of a delete/modify conflict, its stage
  /// content is absent (`showStage` returns null) — keeping that side means
  /// removing the file (`git rm`), never writing empty content (that would
  /// resurrect it as unparseable JSON).
  Future<void> _resolveWholeFile(String root, FileResolution res) async {
    final stage = res.wholeFile == FileSide.incoming ? 2 : 3;
    final content = await _git.showStage(root, res.path, stage);
    if (content == null) {
      await _git.removeFile(root, res.path);
      return;
    }
    await _git.writeWorkingFile(root, res.path, content);
    await _git.add(root, res.path);
  }

  /// Field-level resolutions re-derive the same 3-way merge [_classify]
  /// would produce, then apply [FileResolution.fieldChoices] on top before
  /// serializing.
  Future<String> _resolvedContent(String root, FileResolution res) async {
    return res.path.endsWith('.folder.json')
        ? _resolvedFolderContent(root, res)
        : _resolvedRequestContent(root, res);
  }

  Future<String> _resolvedRequestContent(
    String root,
    FileResolution res,
  ) async {
    final s1 = await _git.showStage(root, res.path, 1);
    final s2 = await _git.showStage(root, res.path, 2);
    final s3 = await _git.showStage(root, res.path, 3);
    final base = _leafOrNull(s1);
    final inc = _leafOrNull(s2);
    final you = _leafOrNull(s3);
    final node = ThreeWayMerge.mergeRequest(base, inc, you);
    final resolved = _applyRequestChoices(
      node.merged,
      res.fieldChoices,
      inc,
      you,
    );
    return _enc.convert(WorkspaceCollectionSerializer.requestToJson(resolved));
  }

  Future<String> _resolvedFolderContent(
    String root,
    FileResolution res,
  ) async {
    final s1 = await _git.showStage(root, res.path, 1);
    final s2 = await _git.showStage(root, res.path, 2);
    final s3 = await _git.showStage(root, res.path, 3);
    final base = _folderOrNull(s1);
    final inc = _folderOrNull(s2);
    final you = _folderOrNull(s3);
    final incOrder = _folderOrderOrEmpty(s2);
    final node = ThreeWayMerge.mergeFolder(
      base,
      _folderOrderOrEmpty(s1),
      inc,
      incOrder,
      you,
      _folderOrderOrEmpty(s3),
    );
    final resolved = _applyFolderChoices(
      node.merged,
      res.fieldChoices,
      inc,
      you,
    );
    // `childOrder` is structural (see ThreeWayMerge.mergeFolder), so it isn't
    // reconstructed from an entity field: `_pick` renders it as a
    // comma-joined string for display, and if the user's choice round-trips
    // that same joining, split it back; otherwise keep the incoming order.
    final orderChoice = res.fieldChoices['child order'];
    final order = orderChoice != null && orderChoice.isNotEmpty
        ? orderChoice.split(', ')
        : incOrder;
    return _enc.convert(
      WorkspaceCollectionSerializer.folderToJson(resolved, order),
    );
  }

  /// Applies request-leaf field picks onto the merged skeleton. Scalar/map
  /// fields apply the chosen string directly; opaque/list fields
  /// (`authentication`, `form fields`) aren't representable as a single
  /// string, so their chosen value must be the literal side marker
  /// `'incoming'` or `'yours'`, and the whole field is taken from that side's
  /// parsed entity.
  CollectionNodeEntity _applyRequestChoices(
    CollectionNodeEntity merged,
    Map<String, String> choices,
    CollectionNodeEntity? incoming,
    CollectionNodeEntity? yours,
  ) {
    var node = merged;
    var config = merged.config;
    for (final entry in choices.entries) {
      final field = entry.key;
      final value = entry.value;
      final headerKey = _bracketedKey(field, "header '");
      if (field == 'name') {
        node = node.copyWith(name: value);
      } else if (field == 'favorite') {
        node = node.copyWith(isFavorite: value == 'true');
      } else if (field == 'method') {
        config = config?.copyWith(method: value);
      } else if (field == 'url') {
        config = config?.copyWith(url: value);
      } else if (field == 'body type') {
        config = config?.copyWith(bodyType: BodyType.fromWire(value));
      } else if (field == 'body') {
        config = config?.copyWith(body: value);
      } else if (field == 'GraphQL variables') {
        config = config?.copyWith(graphqlVariables: value);
      } else if (field == 'binary file') {
        config = config?.copyWith(bodyFilePath: value.isEmpty ? null : value);
      } else if (field == 'authentication') {
        config = config?.copyWith(
          auth: _sideConfig(value, incoming, yours)?.auth ?? const {},
        );
      } else if (field == 'form fields') {
        config = config?.copyWith(
          formFields:
              _sideConfig(value, incoming, yours)?.formFields ?? const [],
        );
      } else if (headerKey != null) {
        final headers = Map<String, String>.from(config?.headers ?? const {});
        headers[headerKey] = value;
        config = config?.copyWith(headers: headers);
      }
    }
    return config == null ? node : node.copyWith(config: config);
  }

  /// Applies folder field picks onto the merged skeleton. `secret keys` is a
  /// list field (same `'incoming'`/`'yours'` side-marker convention as
  /// request-leaf opaque/list fields). `child order` is handled by the
  /// caller — it isn't part of the entity.
  CollectionNodeEntity _applyFolderChoices(
    CollectionNodeEntity merged,
    Map<String, String> choices,
    CollectionNodeEntity? incoming,
    CollectionNodeEntity? yours,
  ) {
    var node = merged;
    final variables = Map<String, String>.from(merged.variables);
    var secretKeys = merged.secretKeys;
    for (final entry in choices.entries) {
      final field = entry.key;
      final value = entry.value;
      final variableKey = _bracketedKey(field, "variable '");
      if (field == 'name') {
        node = node.copyWith(name: value);
      } else if (field == 'favorite') {
        node = node.copyWith(isFavorite: value == 'true');
      } else if (field == 'secret keys') {
        secretKeys =
            (value == 'yours' ? yours : incoming)?.secretKeys ?? const {};
      } else if (variableKey != null) {
        variables[variableKey] = value;
      }
    }
    return node.copyWith(variables: variables, secretKeys: secretKeys);
  }

  static String? _bracketedKey(String field, String prefix) {
    if (!field.startsWith(prefix) || !field.endsWith("'")) return null;
    return field.substring(prefix.length, field.length - 1);
  }

  static HttpRequestConfigEntity? _sideConfig(
    String value,
    CollectionNodeEntity? incoming,
    CollectionNodeEntity? yours,
  ) => (value == 'yours' ? yours : incoming)?.config;

  static CollectionNodeEntity? _leafOrNull(String? json) {
    if (json == null) return null;
    try {
      return WorkspaceCollectionSerializer.requestFromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } on Object catch (_) {
      // Unparseable stage content (malformed JSON or shape mismatch) is
      // reported as a structural conflict by the caller, not a crash.
      return null;
    }
  }

  static CollectionNodeEntity? _folderOrNull(String? json) {
    if (json == null) return null;
    try {
      return WorkspaceCollectionSerializer.folderFromJson(
        jsonDecode(json) as Map<String, dynamic>,
        const [],
      );
    } on Object catch (_) {
      return null;
    }
  }

  static List<String> _folderOrderOrEmpty(String? json) {
    if (json == null) return const [];
    try {
      return WorkspaceCollectionSerializer.childOrder(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } on Object catch (_) {
      return const [];
    }
  }
}

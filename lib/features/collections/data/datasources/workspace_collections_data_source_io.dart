// Native filesystem mirror of the collections forest under a workspace
// directory: one .req.json file per request, a .folder.json + nested
// directory per folder, and a root-order manifest under .getman/. Writes are
// atomic (write to a .tmp file, flush, then rename) and reconcile() deletes
// orphaned files/folders no longer present in the forest — matching names
// case-INsensitively (a case-insensitive filesystem silently redirects a
// write into an existing case-mismatched entry, so a literal-case compare
// would delete just-written data) and, inside an orphaned folder, deleting
// only getman-owned entries so hand-placed files survive. read() throws when
// the root is missing (an unmounted drive must never look like an empty
// workspace) and re-mints duplicated/empty node ids. dart:io is safe here —
// this is the _io.dart half of the io/stub pair selected by
// workspace_data_source_factory.dart.
import 'dart:convert';
import 'dart:io';

import 'package:getman/core/utils/json_file_io.dart' show slugFilename;
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:uuid/uuid.dart';

WorkspaceCollectionsDataSource createWorkspaceDataSource() =>
    _IoWorkspaceDataSource();

class _IoWorkspaceDataSource implements WorkspaceCollectionsDataSource {
  static const String _metaDir = '.getman';
  static const String _manifest = 'workspace.json';
  static const String _folderMeta = '.folder.json';
  static const String _reqExt = '.req.json';

  static const JsonEncoder _enc = JsonEncoder.withIndent('  ');

  // ---- write ----

  @override
  Future<void> write(String root, List<CollectionNodeEntity> forest) async {
    await Directory(root).create(recursive: true);
    final rootOrder = await _writeNodes(root, forest);
    await Directory('$root/$_metaDir').create(recursive: true);
    await _writeJson(
      '$root/$_metaDir/$_manifest',
      WorkspaceCollectionSerializer.manifestToJson(rootOrder),
    );
  }

  /// Writes [nodes] into [dirPath], returns their slugs in order, and deletes
  /// orphaned `.req.json` files / getman folder dirs no longer present.
  Future<List<String>> _writeNodes(
    String dirPath,
    List<CollectionNodeEntity> nodes,
  ) async {
    await Directory(dirPath).create(recursive: true);
    final slugged = _assignSlugs(nodes);
    final expectedReq = <String>{};
    final expectedDir = <String>{};

    for (final entry in slugged) {
      final slug = entry.$1;
      final node = entry.$2;
      if (node.isFolder) {
        expectedDir.add(slug);
        final childDir = '$dirPath/$slug';
        final childOrder = await _writeNodes(childDir, node.children);
        await _writeJson(
          '$childDir/$_folderMeta',
          WorkspaceCollectionSerializer.folderToJson(node, childOrder),
        );
      } else {
        final file = '$slug$_reqExt';
        expectedReq.add(file);
        await _writeJson(
          '$dirPath/$file',
          WorkspaceCollectionSerializer.requestToJson(node),
        );
      }
    }

    await _reconcile(dirPath, expectedReq, expectedDir);
    return [for (final e in slugged) e.$1];
  }

  /// Deletes entries under [dirPath] that the forest no longer contains.
  ///
  /// Names are matched against the expected sets case-INSENSITIVELY, on
  /// purpose: on a case-insensitive filesystem (macOS/Windows defaults)
  /// renaming `x.tmp` onto `login.req.json` when `Login.req.json` already
  /// exists keeps the OLD-case name, and `Directory('payments').create()`
  /// next to an existing `Payments/` is a no-op that redirects children into
  /// the old-case directory — so a literal-case compare would judge the very
  /// entry that ABSORBED the write "orphaned" and delete content written
  /// milliseconds earlier. On a case-sensitive filesystem the worst case of
  /// insensitive matching is keeping a stale same-name-different-case sibling
  /// (two such siblings from a case-sensitive checkout collapse on APFS
  /// anyway) — strictly safer than deleting.
  Future<void> _reconcile(
    String dirPath,
    Set<String> expectedReq,
    Set<String> expectedDir,
  ) async {
    final expectedReqLower = {for (final n in expectedReq) n.toLowerCase()};
    final expectedDirLower = {for (final n in expectedDir) n.toLowerCase()};
    final dir = Directory(dirPath);
    final entities = await dir.list(followLinks: false).toList();
    for (final entity in entities) {
      final name = _basename(entity.path);
      final nameLower = name.toLowerCase();
      if (entity is File &&
          name.endsWith(_reqExt) &&
          !expectedReqLower.contains(nameLower)) {
        await entity.delete();
      } else if (entity is Directory &&
          nameLower != _metaDir &&
          !expectedDirLower.contains(nameLower)) {
        // Only touch directories that are getman folders — and even then
        // delete only getman-owned entries, so hand-placed files survive.
        if (File('${entity.path}/$_folderMeta').existsSync()) {
          await _deleteGetmanOwned(entity);
        }
      }
    }
  }

  /// Deletes only getman-owned entries inside the orphaned folder [dir] —
  /// `.req.json` files, the `.folder.json` marker, leftover `.tmp` halves of
  /// either, and (recursively) subdirectories that are themselves getman
  /// folders — then removes [dir] itself only once it is empty. Foreign,
  /// hand-placed files (README, notes.md, …) and every directory still
  /// holding one are left in place.
  Future<void> _deleteGetmanOwned(Directory dir) async {
    final entries = await dir.list(followLinks: false).toList();
    for (final entry in entries) {
      final name = _basename(entry.path);
      if (entry is File && _isGetmanFile(name)) {
        await entry.delete();
      } else if (entry is Directory &&
          File('${entry.path}/$_folderMeta').existsSync()) {
        await _deleteGetmanOwned(entry);
      }
    }
    if (await dir.list(followLinks: false).isEmpty) {
      await dir.delete();
    }
  }

  /// Whether [name] is a file getman itself writes: request files, the
  /// folder marker, and the transient `.tmp` half of an atomic write (which
  /// only [_writeJson] produces — a crash can leave one behind).
  static bool _isGetmanFile(String name) =>
      name.endsWith(_reqExt) ||
      name == _folderMeta ||
      name.endsWith('$_reqExt.tmp') ||
      name == '$_folderMeta.tmp';

  Future<void> _writeJson(String path, Map<String, dynamic> json) async {
    final tmp = File('$path.tmp');
    // flush: true — without it a power loss after the rename can leave a
    // zero-byte (or truncated) file where valid JSON used to be.
    await tmp.writeAsString(_enc.convert(json), flush: true);
    await tmp.rename(path); // atomic replace
  }

  /// Deterministic, collision-free slugs per sibling group.
  List<(String, CollectionNodeEntity)> _assignSlugs(
    List<CollectionNodeEntity> nodes,
  ) {
    final used = <String>{};
    final result = <(String, CollectionNodeEntity)>[];
    for (final node in nodes) {
      final base = slugFilename(node.name);
      var slug = base;
      if (used.contains(slug)) {
        final suffix = node.id.length >= 6 ? node.id.substring(0, 6) : node.id;
        slug = '$base-$suffix';
        var n = 1;
        while (used.contains(slug)) {
          slug = '$base-$suffix-$n';
          n++;
        }
      }
      used.add(slug);
      result.add((slug, node));
    }
    return result;
  }

  // ---- read ----

  @override
  Future<List<CollectionNodeEntity>> read(String root) async {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      // A missing root (unmounted drive, deleted/renamed folder) must NEVER
      // masquerade as an empty workspace: callers replace the in-app tree
      // with what read() returns, so `[]` here would wipe every collection —
      // saved examples and secret values included. Callers' failure branches
      // are built for a throwing read.
      throw FileSystemException('Workspace directory does not exist', root);
    }
    var order = const <String>[];
    final manifest = File('$root/$_metaDir/$_manifest');
    if (manifest.existsSync()) {
      order = WorkspaceCollectionSerializer.rootOrder(
        (jsonDecode(await manifest.readAsString()) as Map)
            .cast<String, dynamic>(),
      );
    }
    return _readNodes(root, order, <String>{});
  }

  Future<List<CollectionNodeEntity>> _readNodes(
    String dirPath,
    List<String> order,
    Set<String> seenIds,
  ) async {
    final dir = Directory(dirPath);
    // Keys are namespaced per kind ('f:' request file / 'd:' folder dir): a
    // clean git merge can land `foo/` AND `foo.req.json` side by side, and a
    // single shared key would silently drop one of them here — after which
    // the next mirror write would delete it from disk.
    final byKey = <String, CollectionNodeEntity>{};
    final discovered = <String>[];

    final entities = await dir.list(followLinks: false).toList();
    for (final entity in entities) {
      final name = _basename(entity.path);
      if (entity is File && name.endsWith(_reqExt)) {
        final slug = name.substring(0, name.length - _reqExt.length);
        final json = (jsonDecode(await entity.readAsString()) as Map)
            .cast<String, dynamic>();
        byKey['f:$slug'] = _claimUniqueId(
          WorkspaceCollectionSerializer.requestFromJson(json),
          seenIds,
        );
        discovered.add('f:$slug');
      } else if (entity is Directory && name != _metaDir) {
        final metaFile = File('${entity.path}/$_folderMeta');
        if (metaFile.existsSync()) {
          final meta = (jsonDecode(await metaFile.readAsString()) as Map)
              .cast<String, dynamic>();
          final childOrder = WorkspaceCollectionSerializer.childOrder(meta);
          final children = await _readNodes(entity.path, childOrder, seenIds);
          byKey['d:$name'] = _claimUniqueId(
            WorkspaceCollectionSerializer.folderFromJson(meta, children),
            seenIds,
          );
          discovered.add('d:$name');
        }
      }
    }

    // Honor the recorded order first; append anything new found on disk.
    // Order entries are plain slugs, so resolve each against both kinds — a
    // merge-produced folder/file slug collision means one entry names two
    // nodes, and both must survive. Resolution falls back to a
    // case-insensitive match (exact wins): a case-insensitive filesystem
    // (macOS/Windows defaults) can hold "Login.req.json" while the manifest
    // records "login" — the same drift the reconcile pass above tolerates —
    // and an exact-only lookup would silently drop the entry's recorded
    // position, dumping it into the appended-at-the-end bucket.
    final result = <CollectionNodeEntity>[];
    final used = <String>{};
    final byLowerKey = <String, String>{
      for (final key in discovered) key.toLowerCase(): key,
    };
    for (final slug in order) {
      for (final key in ['d:$slug', 'f:$slug']) {
        final resolved = byKey.containsKey(key)
            ? key
            : byLowerKey[key.toLowerCase()];
        if (resolved == null) continue;
        final node = byKey[resolved];
        if (node != null && used.add(resolved)) result.add(node);
      }
    }
    for (final key in discovered) {
      if (!used.contains(key)) result.add(byKey[key]!);
    }
    return result;
  }

  static const Uuid _uuid = Uuid();

  /// Returns [node] with its id claimed as unique within this read,
  /// re-minting a fresh id when the file's id is empty or already taken — a
  /// hand-copied file (`cp login.req.json signup.req.json`) duplicates the id
  /// verbatim, and id-keyed mutations would then hit every copy (a delete
  /// removes both files). The config id is re-minted alongside. The file on
  /// disk is deliberately left untouched: the next mirror write rewrites it
  /// with the new id.
  CollectionNodeEntity _claimUniqueId(
    CollectionNodeEntity node,
    Set<String> seenIds,
  ) {
    if (node.id.isNotEmpty && seenIds.add(node.id)) return node;
    final freshId = _uuid.v4();
    seenIds.add(freshId);
    return CollectionNodeEntity(
      id: freshId,
      name: node.name,
      isFolder: node.isFolder,
      children: node.children,
      config: node.config?.withId(_uuid.v4()),
      isFavorite: node.isFavorite,
      description: node.description,
      examples: node.examples,
      variables: node.variables,
      secretKeys: node.secretKeys,
    );
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}

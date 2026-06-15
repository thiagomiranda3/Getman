import 'dart:convert';
import 'dart:io';

import 'package:getman/core/utils/json_file_io.dart' show slugFilename;
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

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

  Future<void> _reconcile(
    String dirPath,
    Set<String> expectedReq,
    Set<String> expectedDir,
  ) async {
    final dir = Directory(dirPath);
    final entities = await dir.list(followLinks: false).toList();
    for (final entity in entities) {
      final name = _basename(entity.path);
      if (entity is File &&
          name.endsWith(_reqExt) &&
          !expectedReq.contains(name)) {
        await entity.delete();
      } else if (entity is Directory &&
          name != _metaDir &&
          !expectedDir.contains(name)) {
        // Only remove directories that are getman folders.
        if (File('${entity.path}/$_folderMeta').existsSync()) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  Future<void> _writeJson(String path, Map<String, dynamic> json) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(_enc.convert(json));
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
    if (!dir.existsSync()) return const [];
    var order = const <String>[];
    final manifest = File('$root/$_metaDir/$_manifest');
    if (manifest.existsSync()) {
      order = WorkspaceCollectionSerializer.rootOrder(
        (jsonDecode(await manifest.readAsString()) as Map)
            .cast<String, dynamic>(),
      );
    }
    return _readNodes(root, order);
  }

  Future<List<CollectionNodeEntity>> _readNodes(
    String dirPath,
    List<String> order,
  ) async {
    final dir = Directory(dirPath);
    final bySlug = <String, CollectionNodeEntity>{};
    final discovered = <String>[];

    final entities = await dir.list(followLinks: false).toList();
    for (final entity in entities) {
      final name = _basename(entity.path);
      if (entity is File && name.endsWith(_reqExt)) {
        final slug = name.substring(0, name.length - _reqExt.length);
        final json = (jsonDecode(await entity.readAsString()) as Map)
            .cast<String, dynamic>();
        bySlug[slug] = WorkspaceCollectionSerializer.requestFromJson(json);
        discovered.add(slug);
      } else if (entity is Directory && name != _metaDir) {
        final metaFile = File('${entity.path}/$_folderMeta');
        if (metaFile.existsSync()) {
          final meta = (jsonDecode(await metaFile.readAsString()) as Map)
              .cast<String, dynamic>();
          final childOrder = WorkspaceCollectionSerializer.childOrder(meta);
          final children = await _readNodes(entity.path, childOrder);
          bySlug[name] = WorkspaceCollectionSerializer.folderFromJson(
            meta,
            children,
          );
          discovered.add(name);
        }
      }
    }

    // Honor the recorded order first; append anything new found on disk.
    final result = <CollectionNodeEntity>[];
    final used = <String>{};
    for (final slug in order) {
      final node = bySlug[slug];
      if (node != null) {
        result.add(node);
        used.add(slug);
      }
    }
    for (final slug in discovered) {
      if (!used.contains(slug)) result.add(bySlug[slug]!);
    }
    return result;
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}

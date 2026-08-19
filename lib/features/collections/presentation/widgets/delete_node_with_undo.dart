// Shared delete-with-UNDO flow for a collections-tree node, used by both the
// desktop node menu (collection_node_menu.dart) and the phone action sheet
// (node_action_sheet.dart): single request nodes delete INSTANTLY with a 5s
// UNDO snackbar; folders/collection roots keep the ConfirmDialog (bulk
// destruction) and gain the same UNDO snackbar after. Captures the live
// subtree + ancestor chain + sibling index AT DELETE TIME (inside the
// confirm callback, right before dispatching DeleteNode — A10: the tree can
// mutate while the confirm dialog is up via a background git-pull reload or
// Cmd+S saving into the folder, so a dialog-open-time snapshot would make
// UNDO silently drop those interim changes) so RestoreNodeSubtree can put
// everything back — restoring under the nearest surviving ancestor (or root)
// if the parent vanishes meanwhile. If the node itself vanished while the
// dialog was open, the delete is a no-op with an informational snackbar.
//
// Gotcha: only the LATEST snackbar is undoable — a newer delete replaces the
// previous snackbar (standard messenger behavior; accepted loss per spec).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';

/// Undoable-snackbar window (matches the Wave-1 snackbar action convention).
const Duration _undoDuration = Duration(seconds: 5);

/// Deletes [node] with an UNDO snackbar. Folders confirm first; single
/// request nodes delete instantly (A1). [onDeleted] runs right after the
/// delete dispatch — e.g. the phone action sheet pops itself there.
void deleteNodeWithUndo(
  BuildContext context,
  CollectionNodeEntity node, {
  VoidCallback? onDeleted,
}) {
  final bloc = context.read<CollectionsBloc>();
  final messenger = ScaffoldMessenger.of(context);

  void deleteAndOfferUndo() {
    // Capture from LIVE bloc state at delete time — NOT at dialog-open time
    // and NOT the row's build-time copy (A10): for folders the ConfirmDialog
    // await sits between this function being created and being called, and
    // the tree can mutate meanwhile. Snapshotting here guarantees UNDO
    // restores exactly what CONFIRM deleted.
    final collections = bloc.state.collections;
    final snapshot = CollectionsTreeHelper.findNode(collections, node.id);
    if (snapshot == null) {
      // The node vanished while the confirm dialog was up (e.g. a background
      // git pull removed it) — nothing to delete, nothing to offer UNDO for.
      showAppSnackBarVia(messenger, '"${node.name}" no longer exists');
      onDeleted?.call();
      return;
    }
    final ancestorIds = CollectionsTreeHelper.ancestorFolderIds(
      collections,
      node.id,
    );
    final siblingIndex = CollectionsTreeHelper.siblingIndexOf(
      collections,
      node.id,
    );
    bloc.add(DeleteNode(node.id));
    showAppSnackBarVia(
      messenger,
      'Deleted "${node.name}"',
      actionLabel: 'UNDO',
      duration: _undoDuration,
      onAction: () => bloc.add(
        RestoreNodeSubtree(
          node: snapshot,
          ancestorIds: ancestorIds,
          siblingIndex: siblingIndex,
        ),
      ),
    );
    onDeleted?.call();
  }

  if (!node.isFolder) {
    deleteAndOfferUndo();
    return;
  }
  unawaited(
    ConfirmDialog.show(
      context,
      title: 'Delete folder?',
      message: 'Deletes "${node.name}" and everything inside it.',
      onConfirm: deleteAndOfferUndo,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:uuid/uuid.dart';

/// Orchestrates closing a panel with optional save prompts for dirty tabs.
///
/// Flow:
///   1. Bail if the panel is the last one (can't close the last panel).
///   2. Identify dirty tabs via [TabDirtyChecker].
///   3. No dirty tabs → simple confirmation before [RemovePanel].
///   4. Dirty tabs → summary dialog (DISCARD ALL / REVIEW & SAVE / CANCEL).
///   5. REVIEW & SAVE → sequential per-tab dialogs (SAVE / DISCARD /
///      CANCEL REVIEW). On CANCEL REVIEW the panel is NOT removed.
Future<void> closePanelWithSavePrompt(
  BuildContext context,
  String panelId,
) async {
  // --- Capture blocs before any await ----------------------------------------
  final tabsBloc = context.read<TabsBloc>();
  final collectionsBloc = context.read<CollectionsBloc>();
  final dirtyChecker = context.read<TabDirtyChecker>();

  // --- 1. Resolve panel -----------------------------------------------
  final panel = tabsBloc.state.panels.byId(panelId);
  if (panel == null) return;
  if (tabsBloc.state.panels.length <= 1) return; // last panel: no-op

  // --- 2. Compute dirty tabs ------------------------------------------
  final savedConfigs = collectionsBloc.state.configById;
  final dirty = panel.tabs
      .where((tab) => dirtyChecker(tab: tab, savedConfigs: savedConfigs))
      .toList();

  // --- 3. No dirty tabs → simple confirm -------------------------------------
  if (dirty.isEmpty) {
    final count = panel.tabs.length;
    // A panel may be empty (zero tabs); drop the "and its N tabs" clause then.
    final message = count == 0
        ? 'Close "${panel.name}"?'
        : 'Close "${panel.name}" and its $count tab${count == 1 ? '' : 's'}?';
    await ConfirmDialog.show(
      context,
      title: 'CLOSE PANEL?',
      message: message,
      confirmLabel: 'CLOSE',
      onConfirm: () => tabsBloc.add(RemovePanel(panelId)),
    );
    return;
  }

  // --- 4. Dirty tabs → summary dialog ----------------------------------------
  final action = await showResponsiveDialog<_SummaryAction>(
    context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return ResponsiveDialogScaffold(
        title: Text(
          '${panel.name.toUpperCase()} HAS ${dirty.length} UNSAVED TABS',
        ),
        content: Text(
          '${dirty.length} tab${dirty.length == 1 ? '' : 's'} '
          'in "${panel.name}" ${dirty.length == 1 ? 'has' : 'have'} '
          'unsaved changes.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _SummaryAction.cancel),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _SummaryAction.review),
            child: const Text('REVIEW & SAVE…'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _SummaryAction.discardAll),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('DISCARD ALL & CLOSE'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return;

  switch (action) {
    case null:
    case _SummaryAction.cancel:
      return; // no-op

    case _SummaryAction.discardAll:
      tabsBloc.add(RemovePanel(panelId));
      return;

    case _SummaryAction.review:
      break; // fall through to step 5
  }

  // --- 5. Sequential per-tab review ------------------------------------------
  for (final tab in dirty) {
    if (!context.mounted) return;

    final title = tab.displayTitle;
    final perTabAction = await showResponsiveDialog<_PerTabAction>(
      context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return ResponsiveDialogScaffold(
          title: Text("SAVE CHANGES TO '$title'?"),
          content: const Text('Choose how to handle the unsaved changes.'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _PerTabAction.cancelReview),
              child: const Text('CANCEL REVIEW'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _PerTabAction.discard),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('DISCARD'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, _PerTabAction.save),
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;

    switch (perTabAction) {
      case null:
      case _PerTabAction.cancelReview:
        return; // abort — panel stays

      case _PerTabAction.discard:
        continue; // skip this tab, move on

      case _PerTabAction.save:
        final saved = await _saveTab(
          context,
          tab,
          collectionsBloc: collectionsBloc,
        );
        if (!context.mounted) return;
        if (!saved) return; // name prompt cancelled → abort close
    }
  }

  // All tabs reviewed — close the panel
  if (!context.mounted) return;
  context.read<TabsBloc>().add(RemovePanel(panelId));
}

/// Saves [tab] to its linked collection node (if it has one) or prompts the
/// user for a name. Mirrors `_handleSave` / `_showSaveDialog` in
/// `request_view.dart` exactly.
///
/// Returns `true` if the save actually happened, or `false` if the user
/// cancelled the name prompt on an unlinked tab (so the caller can abort the
/// panel-close without discarding unsaved work).
Future<bool> _saveTab(
  BuildContext context,
  HttpRequestTabEntity tab, {
  required CollectionsBloc collectionsBloc,
}) async {
  final tabsBloc = context.read<TabsBloc>();

  final nodeId = tab.collectionNodeId;
  if (nodeId != null) {
    final savedNode = CollectionsTreeHelper.findNode(
      collectionsBloc.state.collections,
      nodeId,
    );
    if (savedNode != null) {
      collectionsBloc.add(UpdateNodeRequest(nodeId, tab.config.copyWith()));
      return true;
    }
    // Node was deleted while the tab was open — drop the stale link.
    tabsBloc.add(
      UpdateTab(tab.copyWith(collectionNodeId: null, collectionName: null)),
    );
  }

  // Unlinked tab (or stale link cleared above) → prompt for a name.
  if (!context.mounted) return false;
  var saved = false;
  await NamePromptDialog.show(
    context,
    title: 'SAVE TO COLLECTION',
    initialText: 'NEW REQUEST',
    hintText: 'REQUEST NAME',
    onConfirm: (name) {
      saved = true;
      final newNodeId = const Uuid().v4();
      collectionsBloc.add(
        SaveRequestToCollection(name, tab.config.copyWith(), id: newNodeId),
      );
      tabsBloc.add(
        UpdateTab(
          tab.copyWith(collectionName: name, collectionNodeId: newNodeId),
        ),
      );
    },
  );
  return saved;
}

enum _SummaryAction { discardAll, review, cancel }

enum _PerTabAction { save, discard, cancelReview }

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Full-height modal bottom sheet that replaces the horizontal tab strip on
/// compact-phone viewports. Each open tab is a row with method badge, title,
/// close button, and drag handle for reorder. Tap a row to switch tabs.
class TabSwitcherSheet extends StatelessWidget {
  const TabSwitcherSheet({required this.onRequestClose, super.key});
  final Future<bool> Function(String tabId) onRequestClose;

  static Future<void> show(
    BuildContext context, {
    required Future<bool> Function(String tabId) onRequestClose,
  }) {
    final tabsBloc = context.read<TabsBloc>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.appShape.sheetRadius),
        ),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: tabsBloc,
        child: TabSwitcherSheet(onRequestClose: onRequestClose),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      // The sheet renders panels + tab list; rebuild when any of these change.
      buildWhen: (prev, next) =>
          prev.tabs != next.tabs ||
          prev.activeIndex != next.activeIndex ||
          prev.panels != next.panels ||
          prev.activePanelId != next.activePanelId,
      builder: (context, state) {
        final tabs = state.tabs;
        final activeIndex = state.activeIndex;
        final panels = state.panels;

        return FractionallySizedBox(
          heightFactor: 0.85,
          child: context.appDecoration.frost(
            context,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(context.appShape.sheetRadius),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor,
                    width: layout.borderThick,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _Header(count: tabs.length),
                  _PanelRow(panels: panels, activePanelId: state.activePanelId),
                  Expanded(
                    child: tabs.isEmpty
                        ? Center(
                            child: Text(
                              'NO OPEN TABS',
                              style: TextStyle(
                                fontSize: layout.fontSizeSubtitle,
                                fontWeight: context.appTypography.displayWeight,
                                color: theme.dividerColor.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            padding: EdgeInsets.all(layout.pagePadding / 2),
                            itemCount: tabs.length,
                            buildDefaultDragHandles: false,
                            onReorder: (oldIndex, newIndex) => context
                                .read<TabsBloc>()
                                .add(ReorderTabs(oldIndex, newIndex)),
                            itemBuilder: (_, index) {
                              final tab = tabs[index];
                              return _TabRow(
                                key: ValueKey('switcher_${tab.tabId}'),
                                tab: tab,
                                index: index,
                                isActive: index == activeIndex,
                                panels: panels,
                                onTap: () {
                                  context.read<TabsBloc>().add(
                                    SetActiveIndex(index),
                                  );
                                  Navigator.of(context).pop();
                                },
                                onClose: () async {
                                  final confirmed = await onRequestClose(
                                    tab.tabId,
                                  );
                                  if (!confirmed || !context.mounted) return;
                                  context.read<TabsBloc>().add(
                                    RemoveTab(tab.tabId),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  _Footer(
                    onNewTab: () {
                      context.read<TabsBloc>().add(const AddTab());
                      Navigator.of(context).pop();
                    },
                    onDismiss: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.headerPaddingVertical,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThick,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'OPEN TABS · $count',
            style: TextStyle(
              fontSize: layout.headerFontSize,
              fontWeight: context.appTypography.displayWeight,
              color: theme.colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrollable row of panel chips, shown above the tab list.
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.panels,
    required this.activePanelId,
  });
  final List<PanelEntity> panels;
  final String activePanelId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: layout.pagePadding / 2,
          vertical: 8,
        ),
        child: Row(
          children: [
            for (final panel in panels)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _PanelChip(
                  key: ValueKey('panel_chip_${panel.id}'),
                  panel: panel,
                  isActive: panel.id == activePanelId,
                ),
              ),
            const _AddPanelChip(key: ValueKey('sheet_add_panel')),
          ],
        ),
      ),
    );
  }
}

/// A single panel chip inside the panel row.
class _PanelChip extends StatelessWidget {
  const _PanelChip({
    required this.panel,
    required this.isActive,
    super.key,
  });
  final PanelEntity panel;
  final bool isActive;

  void _openRename(BuildContext context) {
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'RENAME PANEL',
        initialText: panel.name,
        allowEmpty: true,
        onConfirm: (value) =>
            context.read<TabsBloc>().add(RenamePanel(panel.id, value)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    final foreground = isActive
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final background = isActive
        ? theme.primaryColor
        : theme.colorScheme.surface;

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: InkWell(
        onTap: () => context.read<TabsBloc>().add(SetActivePanel(panel.id)),
        onDoubleTap: () => _openRename(context),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                panel.name,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: isActive
                      ? context.appTypography.displayWeight
                      : context.appTypography.bodyWeight,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.edit, size: layout.iconSize - 2),
                onPressed: () => _openRename(context),
                tooltip: 'RENAME',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                color: foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The trailing "+ New panel" chip in the panel row.
class _AddPanelChip extends StatelessWidget {
  const _AddPanelChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: InkWell(
        onTap: () => context.read<TabsBloc>().add(const AddPanel()),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: layout.iconSize - 2,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 4),
              Text(
                'NEW PANEL',
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.bodyWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tab,
    required this.index,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.panels,
    super.key,
  });
  final HttpRequestTabEntity tab;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final List<PanelEntity> panels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final title = tab.displayTitle;
    // Only show the move popup when there are 2+ panels (one to move from, one
    // to move to). With a single panel there is nowhere to move to.
    final hasMultiplePanels = panels.length > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive ? theme.primaryColor : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.dividerColor, width: layout.borderThin),
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: layout.isCompact ? 10 : 12,
            ),
            child: Row(
              children: [
                MethodBadge(method: tab.config.method),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: context.appTypography.titleWeight,
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (hasMultiplePanels)
                  _MoveToPanelButton(
                    tab: tab,
                    panels: panels,
                    isActive: isActive,
                  ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: layout.iconSize,
                    color: isActive
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.error,
                  ),
                  onPressed: onClose,
                  tooltip: 'CLOSE',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                const SizedBox(width: 4),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle,
                    size: layout.iconSize,
                    color: isActive
                        ? theme.colorScheme.onPrimary
                        : theme.dividerColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Popup menu button for moving a tab to another panel.
class _MoveToPanelButton extends StatelessWidget {
  const _MoveToPanelButton({
    required this.tab,
    required this.panels,
    required this.isActive,
  });
  final HttpRequestTabEntity tab;
  final List<PanelEntity> panels;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final iconColor = isActive
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return PopupMenuButton<_MoveTarget>(
      key: ValueKey('tab_move_panel_${tab.tabId}'),
      icon: Icon(Icons.open_with, size: layout.iconSize, color: iconColor),
      tooltip: 'MOVE TO PANEL',
      onSelected: (target) {
        if (target.newPanel) {
          context.read<TabsBloc>().add(MoveTabToNewPanel(tab.tabId));
        } else {
          context.read<TabsBloc>().add(
            MoveTabToPanel(tab.tabId, target.panelId!),
          );
        }
      },
      itemBuilder: (context) {
        // Exclude the panel that currently owns this tab so the user cannot
        // "move" a tab to its own panel (mirrors the desktop context submenu).
        final ownerPanelId = panels
            .where((p) => p.tabs.any((t) => t.tabId == tab.tabId))
            .map((p) => p.id)
            .firstOrNull;
        final otherPanels = panels.where((p) => p.id != ownerPanelId).toList();
        return [
          for (final panel in otherPanels)
            PopupMenuItem<_MoveTarget>(
              key: ValueKey('tab_move_to_panel_${panel.id}'),
              value: _MoveTarget(panelId: panel.id),
              child: Text(panel.name),
            ),
          PopupMenuItem<_MoveTarget>(
            key: ValueKey('tab_move_to_new_panel_${tab.tabId}'),
            value: const _MoveTarget(newPanel: true),
            child: const Text('NEW PANEL'),
          ),
        ];
      },
    );
  }
}

/// Simple value class to discriminate between "move to existing panel" and
/// "move to a brand-new panel" inside the popup menu.
class _MoveTarget {
  const _MoveTarget({this.panelId, this.newPanel = false});
  final String? panelId;
  final bool newPanel;
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onNewTab, required this.onDismiss});
  final VoidCallback onNewTab;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      padding: EdgeInsets.all(layout.pagePadding / 2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: layout.borderThick),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: context.appDecoration.wrapInteractive(
              child: ElevatedButton.icon(
                onPressed: onNewTab,
                icon: Icon(Icons.add, size: layout.iconSize),
                label: const Text('NEW TAB'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          context.appDecoration.wrapInteractive(
            child: OutlinedButton(
              onPressed: onDismiss,
              child: const Text('CLOSE'),
            ),
          ),
        ],
      ),
    );
  }
}

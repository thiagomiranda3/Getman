import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
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
      // The sheet only renders the tab list + active highlight; skip rebuilds
      // for emissions that change neither (e.g. an isLoading-only flip).
      buildWhen: (prev, next) =>
          prev.tabs != next.tabs || prev.activeIndex != next.activeIndex,
      builder: (context, state) {
        final tabs = state.tabs;
        final activeIndex = state.activeIndex;

        return FractionallySizedBox(
          heightFactor: 0.85,
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
                Expanded(
                  child: tabs.isEmpty
                      ? Center(
                          child: Text(
                            'NO OPEN TABS',
                            style: TextStyle(
                              fontSize: layout.fontSizeSubtitle,
                              fontWeight: context.appTypography.displayWeight,
                              color: theme.dividerColor.withValues(alpha: 0.5),
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

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tab,
    required this.index,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    super.key,
  });
  final HttpRequestTabEntity tab;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final title = tab.displayTitle;

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

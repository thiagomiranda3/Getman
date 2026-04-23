import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

class TabWidget extends StatefulWidget {
  final String tabId;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const TabWidget({
    super.key,
    required this.tabId,
    required this.index,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<TabWidget> createState() => _TabWidgetState();
}

class _TabWidgetState extends State<TabWidget> with TickerProviderStateMixin {
  late AnimationController _sizeController;
  late Animation<double> _sizeAnimation;
  bool _isClosing = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _sizeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _sizeAnimation = CurvedAnimation(
      parent: _sizeController,
      curve: Curves.easeOutCubic,
    );
    _sizeController.forward();
  }

  @override
  void dispose() {
    _sizeController.dispose();
    super.dispose();
  }

  void _handleClose() {
    if (_isClosing) return;
    setState(() => _isClosing = true);
    _sizeController.reverse().then((_) {
      if (mounted) {
        widget.onClose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;

    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
        if (tab == null) return const SizedBox.shrink();

        final dirtyChecker = context.read<TabDirtyChecker>();
        return BlocSelector<CollectionsBloc, CollectionsState, bool>(
          selector: (collState) => dirtyChecker(tab: tab, collections: collState.collections),
          builder: (context, isDirty) {
            final title = tab.collectionName ?? (tab.config.url.isEmpty ? 'NEW REQUEST' : tab.config.url);
            final displayTitle = (title.length > layout.tabTitleMaxLength
                ? '${title.substring(0, layout.tabTitleMaxLength)}...'
                : title).toUpperCase();

            return SizeTransition(
              sizeFactor: _sizeAnimation,
              axis: Axis.horizontal,
              axisAlignment: -1.0,
              child: ReorderableDragStartListener(
                index: widget.index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
                  child: GestureDetector(
                    onTap: widget.onTap,
                    onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: layout.tabBarHeight,
                      constraints: BoxConstraints(
                        minWidth: layout.isCompact ? 80 : 120,
                        maxWidth: layout.isCompact ? 150 : 250,
                      ),
                      padding: EdgeInsets.symmetric(horizontal: layout.tabPaddingHorizontal),
                      decoration: context.appDecoration.tabShape(
                        context,
                        active: widget.isActive,
                        hovered: _isHovered,
                        isFirst: widget.index == 0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: layout.tabFontSize,
                                color: widget.isActive
                                    ? (theme.tabBarTheme.labelColor ?? theme.colorScheme.onSurface)
                                    : (theme.tabBarTheme.unselectedLabelColor ?? theme.colorScheme.onSurface),
                                fontWeight: isDirty ? context.appTypography.displayWeight : (widget.isActive ? context.appTypography.displayWeight : context.appTypography.bodyWeight),
                              ),
                            ),
                          ),
                          if (isDirty)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text('*',
                                  style: TextStyle(
                                      color: theme.colorScheme.secondary,
                                      fontSize: layout.dirtyStarSize,
                                      fontWeight: context.appTypography.displayWeight)),
                            ),
                          SizedBox(width: layout.tabSpacing),
                          IconButton(
                            icon: Icon(Icons.close, size: layout.tabCloseIconSize, color: theme.dividerColor),
                            onPressed: _handleClose,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showContextMenu(BuildContext context, Offset position, HttpRequestTabEntity tab) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;
    final tabsBloc = context.read<TabsBloc>();

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
      ),
      elevation: 0,
      items: <PopupMenuEntry>[
        PopupMenuItem(
          onTap: _handleClose,
          child: _buildMenuItem(context, Icons.close, 'CLOSE'),
        ),
        PopupMenuItem(
          onTap: () => tabsBloc.add(CloseOtherTabs(tab.tabId)),
          child: _buildMenuItem(context, Icons.tab_unselected, 'CLOSE OTHERS'),
        ),
        PopupMenuItem(
          onTap: () => tabsBloc.add(CloseTabsToTheRight(tab.tabId)),
          child: _buildMenuItem(context, Icons.keyboard_double_arrow_right, 'CLOSE TO THE RIGHT'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: () => tabsBloc.add(DuplicateTab(tab.tabId)),
          child: _buildMenuItem(context, Icons.copy, 'DUPLICATE'),
        ),
        PopupMenuItem(
          onTap: () {
            Clipboard.setData(ClipboardData(text: tab.config.url));
          },
          child: _buildMenuItem(context, Icons.link, 'COPY URL'),
        ),
      ],
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        const SizedBox(width: 12),
        Text(text, style: TextStyle(fontWeight: context.appTypography.displayWeight, fontSize: context.appLayout.fontSizeNormal)),
      ],
    );
  }
}

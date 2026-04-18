import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/request_view.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'package:getman/features/home/presentation/widgets/side_menu.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  double? _localSideMenuWidth;

  bool _isTabDirty(BuildContext context, String tabId) {
    final tabsState = context.read<TabsBloc>().state;
    final tab = tabsState.tabs.firstWhereOrNull((t) => t.tabId == tabId);
    if (tab == null) return false;

    if (tab.collectionNodeId == null) {
      return tab.config.url.isNotEmpty || 
             tab.config.body.isNotEmpty || 
             tab.config.params.isNotEmpty || 
             tab.config.headers.isNotEmpty;
    }

    final collectionsState = context.read<CollectionsBloc>().state;
    
    // Helper to find config in tree
    dynamic findConfig(List<dynamic> nodes, String id) {
      for (var node in nodes) {
        if (node.id == id) return node.config;
        final found = findConfig(node.children, id);
        if (found != null) return found;
      }
      return null;
    }

    final savedConfig = findConfig(collectionsState.collections, tab.collectionNodeId!);
    if (savedConfig == null) return true;
    
    return tab.config != savedConfig;
  }

  void _confirmClose(BuildContext context, int index) {
    final tabsBloc = context.read<TabsBloc>();
    if (index < 0 || index >= tabsBloc.state.tabs.length) return;
    
    final tab = tabsBloc.state.tabs[index];
    final isDirty = _isTabDirty(context, tab.tabId);
    
    void performRemove() {
      tabsBloc.add(RemoveTab(index));
    }

    if (isDirty) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('UNSAVED CHANGES'),
          content: const Text('YOU HAVE UNSAVED CHANGES. ARE YOU SURE YOU WANT TO CLOSE THIS TAB?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                performRemove();
              },
              child: const Text('CLOSE ANYWAY', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      performRemove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final settings = settingsState.settings;
        final currentSideMenuWidth = _localSideMenuWidth ?? settings.sideMenuWidth;

        return BlocBuilder<TabsBloc, TabsState>(
          builder: (context, tabsState) {
            final activeIndex = tabsState.activeIndex;
            final tabs = tabsState.tabs;

            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => context.read<TabsBloc>().add(const AddTab()),
                const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => context.read<TabsBloc>().add(const AddTab()),
                const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _confirmClose(context, activeIndex),
                const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => _confirmClose(context, activeIndex),
              },
              child: Scaffold(
                body: Row(
                  children: [
                    SizedBox(
                      width: currentSideMenuWidth,
                      child: const SideMenu(),
                    ),
                    Splitter(
                      isVertical: false,
                      onUpdate: (delta) {
                        setState(() {
                          _localSideMenuWidth = (currentSideMenuWidth + delta).clamp(200.0, 600.0);
                        });
                      },
                      onEnd: () {
                        if (_localSideMenuWidth != null) {
                          context.read<SettingsBloc>().add(UpdateSideMenuWidth(_localSideMenuWidth!));
                        }
                      },
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _buildTabBar(context, activeIndex, tabs),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                              child: tabsState.isLoading 
                                ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
                                : tabs.isEmpty
                                  ? Center(
                                      key: const ValueKey('empty'),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.bolt, size: 64, color: theme.dividerColor.withValues(alpha: 0.3)),
                                          const SizedBox(height: 16),
                                          Text(
                                            'NO OPEN TABS',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: theme.dividerColor.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'PRESS CTRL+N TO CREATE A NEW REQUEST',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: theme.dividerColor.withValues(alpha: 0.2),
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          BrutalBounce(
                                            child: ElevatedButton(
                                              onPressed: () => context.read<TabsBloc>().add(const AddTab()),
                                              style: ElevatedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                              ),
                                              child: const Text('NEW REQUEST'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : RequestView(
                                      key: ValueKey('view_${tabs[activeIndex].tabId}'),
                                      tabId: tabs[activeIndex].tabId,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabBar(BuildContext context, int activeIndex, List<dynamic> tabs) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<LayoutExtension>()!;

    return Container(
      height: layout.tabBarHeight,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) => context.read<TabsBloc>().add(ReorderTabs(oldIndex, newIndex)),
              proxyDecorator: (child, index, animation) => Material(
                color: theme.scaffoldBackgroundColor,
                elevation: 4,
                child: child,
              ),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return _TabWidget(
                  key: ValueKey('tab_${tab.tabId}'),
                  tabId: tab.tabId,
                  index: index,
                  isActive: activeIndex == index,
                  onTap: () => context.read<TabsBloc>().add(SetActiveIndex(index)),
                  onClose: () => _confirmClose(context, index),
                );
              },
            ),
          ),
          _AddTabButton(layout: layout),
        ],
      ),
    );
  }
}

class _AddTabButton extends StatefulWidget {
  final LayoutExtension layout;

  const _AddTabButton({required this.layout});

  @override
  State<_AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends State<_AddTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isHovered ? theme.primaryColor : theme.scaffoldBackgroundColor,
          border: Border(left: BorderSide(color: theme.dividerColor, width: 3)),
        ),
        child: BrutalBounce(
          child: IconButton(
            icon: Icon(Icons.add, size: widget.layout.addIconSize, color: theme.colorScheme.onSurface),
            onPressed: () => context.read<TabsBloc>().add(const AddTab()),
          ),
        ),
      ),
    );
  }
}

class _TabWidget extends StatefulWidget {
  final String tabId;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabWidget({
    super.key,
    required this.tabId,
    required this.index,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_TabWidget> createState() => _TabWidgetState();
}

class _TabWidgetState extends State<_TabWidget> with TickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _sizeController;
  late Animation<double> _sizeAnimation;
  bool _isClosing = false;

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
    final layout = theme.extension<LayoutExtension>()!;

    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
        if (tab == null) return const SizedBox.shrink();

        return BlocBuilder<CollectionsBloc, CollectionsState>(
          builder: (context, collState) {
            final isDirty = _isTabDirtyInternal(tab, collState.collections);
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
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onTap,
                    onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, tab, widget.index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: layout.tabBarHeight,
                      constraints: BoxConstraints(
                        minWidth: layout.isCompact ? 80 : 120,
                        maxWidth: layout.isCompact ? 150 : 250,
                      ),
                      padding: EdgeInsets.symmetric(horizontal: layout.tabPaddingHorizontal),
                      decoration: BoxDecoration(
                        color: widget.isActive 
                            ? theme.primaryColor 
                            : (_isHovered ? theme.dividerColor.withValues(alpha: 0.2) : theme.scaffoldBackgroundColor),
                        border: Border(
                          top: BorderSide(color: theme.dividerColor, width: 3),
                          left: widget.index == 0 ? BorderSide(color: theme.dividerColor, width: 3) : BorderSide.none,
                          right: BorderSide(color: theme.dividerColor, width: 3),
                          bottom: widget.isActive ? BorderSide.none : BorderSide(color: theme.dividerColor, width: 3),
                        ),
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
                                color: widget.isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                fontWeight: isDirty ? FontWeight.w900 : (widget.isActive ? FontWeight.w900 : FontWeight.w500),
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
                                      fontWeight: FontWeight.w900)),
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

  bool _isTabDirtyInternal(dynamic tab, List<dynamic> collections) {
     if (tab.collectionNodeId == null) {
      return tab.config.url.isNotEmpty || 
             tab.config.body.isNotEmpty || 
             tab.config.params.isNotEmpty || 
             tab.config.headers.isNotEmpty;
    }

    dynamic findConfig(List<dynamic> nodes, String id) {
      for (var node in nodes) {
        if (node.id == id) return node.config;
        final found = findConfig(node.children, id);
        if (found != null) return found;
      }
      return null;
    }

    final savedConfig = findConfig(collections, tab.collectionNodeId!);
    if (savedConfig == null) return true;
    
    return tab.config != savedConfig;
  }

  void _showContextMenu(BuildContext context, Offset position, dynamic tab, int index) {
    final theme = Theme.of(context);
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
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: theme.dividerColor, width: 3),
      ),
      elevation: 0,
      items: <PopupMenuEntry>[
        PopupMenuItem(
          onTap: _handleClose,
          child: _buildMenuItem(context, Icons.close, 'CLOSE'),
        ),
        PopupMenuItem(
          onTap: () => tabsBloc.add(CloseOtherTabs(index)),
          child: _buildMenuItem(context, Icons.tab_unselected, 'CLOSE OTHERS'),
        ),
        PopupMenuItem(
          onTap: () => tabsBloc.add(CloseTabsToTheRight(index)),
          child: _buildMenuItem(context, Icons.keyboard_double_arrow_right, 'CLOSE TO THE RIGHT'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: () => tabsBloc.add(DuplicateTab(index)),
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
        Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ],
    );
  }
}

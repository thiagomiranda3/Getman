import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/request_view.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/features/home/presentation/widgets/side_menu.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  double? _localSideMenuWidth;
  final FocusNode _mainFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    super.dispose();
  }

  bool _isTabDirty(BuildContext context, String tabId) {
    final tab = context.read<TabsBloc>().state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
    if (tab == null) return false;
    return context.read<TabDirtyChecker>()(
      tab: tab,
      collections: context.read<CollectionsBloc>().state.collections,
    );
  }

  void _confirmClose(BuildContext context, String tabId) {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
    if (tab == null) return;

    final isDirty = _isTabDirty(context, tabId);

    void performRemove() {
      tabsBloc.add(RemoveTab(tabId));
    }

    if (isDirty) {
      showDialog(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: const Text('UNSAVED CHANGES'),
            content: const Text('YOU HAVE UNSAVED CHANGES. ARE YOU SURE YOU WANT TO CLOSE THIS TAB?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  performRemove();
                },
                child: Text('CLOSE ANYWAY',
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
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

            return Actions(
              actions: <Type, Action<Intent>>{
                CloseTabIntent: CallbackAction<CloseTabIntent>(
                  onInvoke: (_) {
                    if (activeIndex < 0 || activeIndex >= tabs.length) return null;
                    _confirmClose(context, tabs[activeIndex].tabId);
                    return null;
                  },
                ),
                SendRequestIntent: CallbackAction<SendRequestIntent>(
                  onInvoke: (_) {
                    if (activeIndex >= 0 && activeIndex < tabs.length && !tabs[activeIndex].isSending) {
                      context.read<TabsBloc>().add(const SendRequest());
                    }
                    return null;
                  },
                ),
              },
              child: Focus(
                focusNode: _mainFocusNode,
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
                          final committed = _localSideMenuWidth;
                          if (committed == null) return;
                          context.read<SettingsBloc>().add(UpdateSideMenuWidth(committed));
                          setState(() => _localSideMenuWidth = null);
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
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabBar(BuildContext context, int activeIndex, List<HttpRequestTabEntity> tabs) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<LayoutExtension>()!;

    return Container(
      height: layout.tabBarHeight,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: layout.borderThick)),
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
                  onClose: () => _confirmClose(context, tab.tabId),
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
          border: Border(left: BorderSide(color: theme.dividerColor, width: widget.layout.borderThick)),
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
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
                  cursor: SystemMouseCursors.click,
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
                      decoration: BoxDecoration(
                        color: widget.isActive
                            ? theme.primaryColor
                            : (_isHovered ? theme.dividerColor.withValues(alpha: 0.2) : theme.scaffoldBackgroundColor),
                        border: Border(
                          top: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                          left: widget.index == 0 ? BorderSide(color: theme.dividerColor, width: layout.borderThick) : BorderSide.none,
                          right: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                          bottom: widget.isActive ? BorderSide.none : BorderSide(color: theme.dividerColor, width: layout.borderThick),
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

  void _showContextMenu(BuildContext context, Offset position, HttpRequestTabEntity tab) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;
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
        Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ],
    );
  }
}

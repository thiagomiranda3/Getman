import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:collection/collection.dart';
import 'services/storage_service.dart';
import 'widgets/side_menu.dart';
import 'widgets/request_view.dart';
import 'widgets/splitter.dart';
import 'providers/tabs_provider.dart';
import 'utils/neo_brutalist_theme.dart';

import 'providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
    Widget build(BuildContext context, WidgetRef ref) {
      final settings = ref.watch(settingsProvider);
      
      return MaterialApp(
        title: 'GETMAN',
        debugShowCheckedModeBanner: false,
        theme: NeoBrutalistTheme.theme(Brightness.light, isCompact: settings.isCompactMode),
        darkTheme: NeoBrutalistTheme.theme(Brightness.dark, isCompact: settings.isCompactMode),
        themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: const MainScreen(),
      );
    }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  double? _localSideMenuWidth;

  @override
  Widget build(BuildContext context) {
    final activeIndex = ref.watch(tabsProvider.select((s) => s.activeIndex));
    final tabIds = ref.watch(tabsProvider.select((s) => s.tabs.map((t) => t.tabId).toList()));
    final tabsNotifier = ref.read(tabsProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final currentSideMenuWidth = _localSideMenuWidth ?? settings.sideMenuWidth;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => tabsNotifier.addTab(),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => tabsNotifier.addTab(),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _confirmClose(context, activeIndex, ref),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => _confirmClose(context, activeIndex, ref),
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
                  ref.read(settingsProvider.notifier).updateSideMenuWidth(_localSideMenuWidth!);
                }
              },
            ),
            Expanded(
              child: Column(
                children: [
                  _buildTabBar(context, activeIndex, tabIds, tabsNotifier, ref),
                  Expanded(
                    child: IndexedStack(
                      index: activeIndex,
                      children: tabIds.map((id) => RequestView(key: ValueKey('view_$id'), tabId: id)).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClose(BuildContext context, int index, WidgetRef ref) {
    final tab = ref.read(tabsProvider).tabs[index];
    final isDirty = ref.read(isTabDirtyProvider(tab.tabId));
    
    // We'll use a local function to handle actual state removal
    void performRemove() {
      ref.read(tabsProvider.notifier).removeTab(index);
    }

    if (isDirty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('UNSAVED CHANGES'),
          content: const Text('YOU HAVE UNSAVED CHANGES. ARE YOU SURE YOU WANT TO CLOSE THIS TAB?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
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

  Widget _buildTabBar(BuildContext context, int activeIndex, List<String> tabIds, TabsNotifier notifier, WidgetRef ref) {
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
              itemCount: tabIds.length,
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) => notifier.reorderTabs(oldIndex, newIndex),
              proxyDecorator: (child, index, animation) => Material(
                color: theme.scaffoldBackgroundColor,
                elevation: 4,
                child: child,
              ),
              itemBuilder: (context, index) {
                final tabId = tabIds[index];
                return _TabWidget(
                  key: ValueKey('tab_$tabId'),
                  tabId: tabId,
                  index: index,
                  isActive: activeIndex == index,
                  onTap: () => notifier.setActiveIndex(index),
                  onClose: () => _confirmClose(context, index, ref),
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.dividerColor, width: 3)),
            ),
            child: BrutalBounce(
              child: IconButton(
                icon: Icon(Icons.add, size: layout.addIconSize, color: theme.colorScheme.onSurface),
                onPressed: () => notifier.addTab(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabWidget extends ConsumerStatefulWidget {
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
  ConsumerState<_TabWidget> createState() => _TabWidgetState();
}

class _TabWidgetState extends ConsumerState<_TabWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context) {
    if (_tapPosition == null) return;

    final theme = Theme.of(context);
    final tabsNotifier = ref.read(tabsProvider.notifier);
    final tab = ref.read(tabsProvider).tabs[widget.index];

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        _tapPosition!.dx,
        _tapPosition!.dy,
        _tapPosition!.dx + 1,
        _tapPosition!.dy + 1,
      ),
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: theme.dividerColor, width: 3),
      ),
      elevation: 0,
      items: <PopupMenuEntry>[
        PopupMenuItem(
          onTap: () => widget.onClose(),
          child: _buildMenuItem(Icons.close, 'CLOSE'),
        ),
        PopupMenuItem(
          onTap: () => tabsNotifier.closeOtherTabs(widget.index),
          child: _buildMenuItem(Icons.tab_unselected, 'CLOSE OTHERS'),
        ),
        PopupMenuItem(
          onTap: () => tabsNotifier.closeTabsToTheRight(widget.index),
          child: _buildMenuItem(Icons.keyboard_double_arrow_right, 'CLOSE TO THE RIGHT'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: () => tabsNotifier.duplicateTab(widget.index),
          child: _buildMenuItem(Icons.copy, 'DUPLICATE'),
        ),
        PopupMenuItem(
          onTap: () {
            Clipboard.setData(ClipboardData(text: tab.config.url));
          },
          child: _buildMenuItem(Icons.link, 'COPY URL'),
        ),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<LayoutExtension>()!;
    final tab = ref.watch(tabsProvider.select((s) => s.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId)));
    if (tab == null) return const SizedBox.shrink();

    final isDirty = ref.watch(isTabDirtyProvider(widget.tabId));
    final title = tab.collectionName ?? (tab.config.url.isEmpty ? 'NEW REQUEST' : tab.config.url);
    final displayTitle = (title.length > layout.tabTitleMaxLength
        ? '${title.substring(0, layout.tabTitleMaxLength)}...' 
        : title).toUpperCase();

    return ReorderableDragStartListener(
      index: widget.index,
      child: FadeTransition(
        opacity: _animation,
        child: SizeTransition(
          sizeFactor: _animation,
          axis: Axis.horizontal,
          axisAlignment: -1.0,
          child: Listener(
            onPointerDown: (event) {
              if (event.buttons == kMiddleMouseButton) {
                _handleClose();
              }
            },
            child: GestureDetector(
              onTap: widget.onTap,
              onSecondaryTapDown: (details) {
                _tapPosition = details.globalPosition;
              },
              onSecondaryTap: () => _showContextMenu(context),
              child: Container(
                height: layout.tabBarHeight,
                constraints: BoxConstraints(
                  minWidth: layout.isCompact ? 80 : 120,
                  maxWidth: layout.isCompact ? 150 : 250,
                ),
                padding: EdgeInsets.symmetric(horizontal: layout.tabPaddingHorizontal),
                decoration: BoxDecoration(
                  color: widget.isActive ? theme.primaryColor : theme.scaffoldBackgroundColor,
                  border: Border(
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
                          color: theme.colorScheme.onSurface,
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
      ),
    );
  }

  void _handleClose() async {
    await _controller.reverse();
    widget.onClose();
  }
}


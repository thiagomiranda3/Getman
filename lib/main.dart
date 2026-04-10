import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:collection/collection.dart';
import 'services/storage_service.dart';
import 'widgets/side_menu.dart';
import 'widgets/request_view.dart';
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

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIndex = ref.watch(tabsProvider.select((s) => s.activeIndex));
    final tabIds = ref.watch(tabsProvider.select((s) => s.tabs.map((t) => t.tabId).toList()));
    final tabsNotifier = ref.read(tabsProvider.notifier);

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
            const SideMenu(),
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
                ref.read(tabsProvider.notifier).removeTab(index);
                Navigator.pop(context);
              },
              child: const Text('CLOSE ANYWAY', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      ref.read(tabsProvider.notifier).removeTab(index);
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
                color: Colors.transparent,
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
            child: IconButton(
              icon: Icon(Icons.add, size: layout.addIconSize, color: theme.colorScheme.onSurface),
              onPressed: () => notifier.addTab(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabWidget extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<LayoutExtension>()!;
    final tab = ref.watch(tabsProvider.select((s) => s.tabs.firstWhereOrNull((t) => t.tabId == tabId)));
    if (tab == null) return const SizedBox.shrink();

    final isDirty = ref.watch(isTabDirtyProvider(tabId));
    final title = tab.collectionName ?? (tab.config.url.isEmpty ? 'NEW REQUEST' : tab.config.url);
    final displayTitle = (title.length > layout.tabTitleMaxLength
        ? '${title.substring(0, layout.tabTitleMaxLength)}...' 
        : title).toUpperCase();

    return ReorderableDragStartListener(
      index: index,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kMiddleMouseButton) {
            onClose();
          }
        },
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: layout.tabPaddingHorizontal),
            decoration: BoxDecoration(
              color: isActive ? theme.primaryColor : Colors.transparent,
              border: Border(
                right: BorderSide(color: theme.dividerColor, width: 3),
                bottom: isActive ? BorderSide.none : BorderSide(color: theme.dividerColor, width: 3),
              ),
            ),
            child: Row(
              children: [
                Text(
                  displayTitle,
                  style: TextStyle(
                    fontSize: layout.tabFontSize,
                    color: theme.colorScheme.onSurface,
                    fontWeight: isDirty ? FontWeight.w900 : (isActive ? FontWeight.w900 : FontWeight.w500),
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
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


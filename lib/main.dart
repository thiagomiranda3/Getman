import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'services/storage_service.dart';
import 'widgets/side_menu.dart';
import 'widgets/request_view.dart';
import 'providers/tabs_provider.dart';
import 'providers/collections_provider.dart';
import 'models/request_tab.dart';
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
      theme: NeoBrutalistTheme.lightTheme,
      darkTheme: NeoBrutalistTheme.darkTheme,
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

    return Scaffold(
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
    );
  }

  bool _isTabDirty(HttpRequestTabModel tab, WidgetRef ref) {
    if (tab.collectionNodeId == null) return false;
    final savedConfig = ref.read(collectionsProvider.notifier).getConfig(tab.collectionNodeId!);
    if (savedConfig == null) return false;
    
    final currentJson = json.encode(tab.config.toJson());
    final savedJson = json.encode(savedConfig.toJson());
    return currentJson != savedJson;
  }

  void _confirmClose(BuildContext context, int index, WidgetRef ref) {
    final tab = ref.read(tabsProvider).tabs[index];
    if (_isTabDirty(tab, ref)) {
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
    final settings = ref.watch(settingsProvider);

    return Container(
      height: settings.isCompactMode ? 40 : 60,
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
                // We need the tab data for the title and dirty state
                // Since this is inside a builder, we can't use ref.watch easily for every tab
                // but we can use a Consumer here if we want to be super efficient.
                return Consumer(
                  key: ValueKey('tab_$tabId'),
                  builder: (context, ref, _) {
                    final tab = ref.watch(tabsProvider.select((s) => s.tabs.firstWhere((t) => t.tabId == tabId)));
                    final isActive = activeIndex == index;
                    final isDirty = _isTabDirty(tab, ref);
                    final title = tab.collectionName ?? (tab.config.url.isEmpty ? 'NEW REQUEST' : tab.config.url);
                    final displayTitle = (title.length > (settings.isCompactMode ? 15 : 25) ? '${title.substring(0, (settings.isCompactMode ? 15 : 25))}...' : title).toUpperCase();

                    return ReorderableDragStartListener(
                      index: index,
                      child: Listener(
                        onPointerDown: (event) {
                          if (event.buttons == kMiddleMouseButton) {
                            _confirmClose(context, index, ref);
                          }
                        },
                        child: GestureDetector(
                          onTap: () => notifier.setActiveIndex(index),
                          child: Container(
                          padding: EdgeInsets.symmetric(horizontal: settings.isCompactMode ? 8 : 16),
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
                                  fontSize: settings.isCompactMode ? 9 : 11,
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: isDirty ? FontWeight.w900 : (isActive ? FontWeight.w900 : FontWeight.w500),
                                ),
                              ),
                              if (isDirty) 
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text('*', style: TextStyle(color: theme.colorScheme.secondary, fontSize: settings.isCompactMode ? 12 : 16, fontWeight: FontWeight.w900)),
                                ),
                              SizedBox(width: settings.isCompactMode ? 4 : 8),
                              IconButton(
                                icon: Icon(Icons.close, size: settings.isCompactMode ? 12 : 16, color: theme.dividerColor),
                                onPressed: () => _confirmClose(context, index, ref),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.dividerColor, width: 3)),
            ),
            child: IconButton(
              icon: Icon(Icons.add, size: settings.isCompactMode ? 18 : 24, color: theme.colorScheme.onSurface),
              onPressed: () => notifier.addTab(),
            ),
          ),
        ],
      ),
    );
  }
}


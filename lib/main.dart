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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GETMAN',
      debugShowCheckedModeBanner: false,
      theme: NeoBrutalistTheme.theme,
      darkTheme: NeoBrutalistTheme.theme,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsState = ref.watch(tabsProvider);
    final tabsNotifier = ref.read(tabsProvider.notifier);

    return Scaffold(
      body: Row(
        children: [
          const SideMenu(),
          Expanded(
            child: Column(
              children: [
                _buildTabBar(context, tabsState, tabsNotifier, ref),
                Expanded(
                  child: IndexedStack(
                    index: tabsState.activeIndex,
                    children: tabsState.tabs.map((tab) => RequestView(key: ValueKey('view_${tab.tabId}'), tab: tab)).toList(),
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

  Widget _buildTabBar(BuildContext context, TabsState state, TabsNotifier notifier, WidgetRef ref) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: NeoBrutalistTheme.background,
        border: Border(bottom: BorderSide(color: NeoBrutalistTheme.border, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.tabs.length,
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) => notifier.reorderTabs(oldIndex, newIndex),
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                child: child,
              ),
              itemBuilder: (context, index) {
                final tab = state.tabs[index];
                final isActive = state.activeIndex == index;
                final isDirty = _isTabDirty(tab, ref);
                final title = tab.collectionName ?? (tab.config.url.isEmpty ? 'NEW REQUEST' : tab.config.url);
                final displayTitle = (title.length > 25 ? '${title.substring(0, 25)}...' : title).toUpperCase();

                return ReorderableDragStartListener(
                  key: ValueKey('tab_${tab.tabId}'),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isActive ? NeoBrutalistTheme.primary : Colors.transparent,
                        border: Border(
                          right: const BorderSide(color: NeoBrutalistTheme.border, width: 3),
                          bottom: isActive ? BorderSide.none : const BorderSide(color: NeoBrutalistTheme.border, width: 3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            displayTitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: NeoBrutalistTheme.text,
                              fontWeight: isDirty ? FontWeight.w900 : (isActive ? FontWeight.w900 : FontWeight.w500),
                            ),
                          ),
                          if (isDirty) 
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text('*', style: TextStyle(color: NeoBrutalistTheme.secondary, fontSize: 16, fontWeight: FontWeight.w900)),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: NeoBrutalistTheme.border),
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
          ),
        ),
          Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: NeoBrutalistTheme.border, width: 3)),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, size: 24, color: NeoBrutalistTheme.text),
              onPressed: () => notifier.addTab(),
            ),
          ),
        ],
      ),
    );
  }
}


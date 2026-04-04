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
      title: 'Getman',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
      ),
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
                    children: tabsState.tabs.map((tab) => RequestView(key: ValueKey(tab.config.id), tab: tab)).toList(),
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
          title: const Text('Unsaved Changes'),
          content: const Text('You have unsaved changes. Are you sure you want to close this tab?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                ref.read(tabsProvider.notifier).removeTab(index);
                Navigator.pop(context);
              },
              child: const Text('Close Anyway', style: TextStyle(color: Colors.red)),
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
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).secondaryHeaderColor.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.tabs.length,
              itemBuilder: (context, index) {
                final tab = state.tabs[index];
                final isActive = state.activeIndex == index;
                final isDirty = _isTabDirty(tab, ref);
                final title = tab.collectionName ?? (tab.config.url.isEmpty ? 'New Request' : tab.config.url);
                final displayTitle = title.length > 20 ? '${title.substring(0, 20)}...' : title;

                return Listener(
                  onPointerDown: (event) {
                    if (event.buttons == kMiddleMouseButton) {
                      _confirmClose(context, index, ref);
                    }
                  },
                  child: GestureDetector(
                    onTap: () => notifier.setActiveIndex(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isActive ? Theme.of(context).canvasColor : Colors.transparent,
                        border: Border(
                          right: BorderSide(color: Colors.grey.shade300),
                          top: isActive ? BorderSide(color: Theme.of(context).primaryColor, width: 2) : BorderSide.none,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            displayTitle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isDirty ? FontWeight.bold : (isActive ? FontWeight.bold : FontWeight.normal),
                              fontStyle: isDirty ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, size: 14),
                            onPressed: () => _confirmClose(context, index, ref),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: () => notifier.addTab(),
          ),
        ],
      ),
    );
  }
}

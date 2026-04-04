import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/storage_service.dart';
import 'widgets/side_menu.dart';
import 'widgets/request_view.dart';
import 'providers/tabs_provider.dart';

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
                _buildTabBar(context, tabsState, tabsNotifier),
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

  Widget _buildTabBar(BuildContext context, TabsState state, TabsNotifier notifier) {
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
                return GestureDetector(
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
                          tab.config.url.isEmpty ? 'New Request' : (tab.config.url.length > 20 ? '${tab.config.url.substring(0, 20)}...' : tab.config.url),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          onPressed: () => notifier.removeTab(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
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

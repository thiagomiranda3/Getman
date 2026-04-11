import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import '../models/request_tab.dart';
import '../models/request_config.dart';
import '../models/collection_node.dart';
import '../services/storage_service.dart';
import 'history_provider.dart';
import 'settings_provider.dart';
import 'dio_provider.dart';
import 'collections_provider.dart';

class TabsState {
  final List<HttpRequestTabModel> tabs;
  final int activeIndex;

  TabsState({required this.tabs, required this.activeIndex});

  TabsState copyWith({List<HttpRequestTabModel>? tabs, int? activeIndex}) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}

class TabsNotifier extends StateNotifier<TabsState> {
  final Ref ref;
  Timer? _debounceTimer;
  final Map<String, CancelToken> _cancelTokens = {};

  TabsNotifier(this.ref) : super(_loadInitialState());

  static TabsState _loadInitialState() {
    final tabs = StorageService.getTabs();
    if (tabs.isEmpty) {
      return TabsState(
        tabs: [HttpRequestTabModel(config: HttpRequestConfig(url: ''))],
        activeIndex: 0,
      );
    }
    
    // Ensure all tabs have unique IDs to avoid ReorderableListView key conflicts
    final Set<String> seenIds = {};
    final List<HttpRequestTabModel> uniqueTabs = [];
    for (var tab in tabs) {
      if (seenIds.contains(tab.tabId)) {
        uniqueTabs.add(tab.copyWith(tabId: const Uuid().v4()));
      } else {
        uniqueTabs.add(tab);
        seenIds.add(tab.tabId);
      }
    }

    return TabsState(tabs: uniqueTabs, activeIndex: 0);
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 10), () {
      StorageService.saveTabs(state.tabs);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    StorageService.saveTabs(state.tabs); // Final save on dispose
    super.dispose();
  }

  void addTab({HttpRequestConfig? config, String? collectionNodeId, String? collectionName}) {
    if (collectionNodeId != null) {
      final existingIndex = state.tabs.indexWhere((t) => t.collectionNodeId == collectionNodeId);
      if (existingIndex != -1) {
        state = state.copyWith(activeIndex: existingIndex);
        return;
      }
    }

    final newTab = HttpRequestTabModel(
      config: config ?? HttpRequestConfig(),
      collectionNodeId: collectionNodeId,
      collectionName: collectionName,
    );
    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeIndex: state.tabs.length,
    );
    _scheduleSave();
  }

  void removeTab(int index) {
    if (state.tabs.length <= 1) return;

    final newTabs = [...state.tabs]..removeAt(index);
    int newActiveIndex = state.activeIndex;
    if (newActiveIndex >= newTabs.length) {
      newActiveIndex = newTabs.length - 1;
    }
    state = state.copyWith(tabs: newTabs, activeIndex: newActiveIndex);
    _scheduleSave();
  }

  void setActiveIndex(int index) {
    if (state.activeIndex == index) return;
    state = state.copyWith(activeIndex: index);
  }

  void reorderTabs(int oldIndex, int newIndex) {
    final tabs = [...state.tabs];
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, item);

    int newActiveIndex = state.activeIndex;
    if (oldIndex == state.activeIndex) {
      newActiveIndex = newIndex;
    } else if (oldIndex < state.activeIndex && newIndex >= state.activeIndex) {
      newActiveIndex -= 1;
    } else if (oldIndex > state.activeIndex && newIndex <= state.activeIndex) {
      newActiveIndex += 1;
    }

    state = state.copyWith(tabs: tabs, activeIndex: newActiveIndex);
    _scheduleSave();
  }

  void updateCurrentTab(HttpRequestTabModel tab) {
    if (state.tabs[state.activeIndex] == tab) return;
    final newTabs = [...state.tabs];
    newTabs[state.activeIndex] = tab;
    state = state.copyWith(tabs: newTabs);
    _scheduleSave();
  }

  void closeOtherTabs(int index) {
    if (state.tabs.length <= 1) return;
    final tabToKeep = state.tabs[index];
    state = state.copyWith(
      tabs: [tabToKeep],
      activeIndex: 0,
    );
    _scheduleSave();
  }

  void closeTabsToTheRight(int index) {
    if (index >= state.tabs.length - 1) return;
    final newTabs = state.tabs.sublist(0, index + 1);
    int newActiveIndex = state.activeIndex;
    if (newActiveIndex > index) {
      newActiveIndex = index;
    }
    state = state.copyWith(
      tabs: newTabs,
      activeIndex: newActiveIndex,
    );
    _scheduleSave();
  }

  void duplicateTab(int index) {
    final tabToDuplicate = state.tabs[index];
    final duplicatedTab = HttpRequestTabModel(
      config: tabToDuplicate.config.copyWith(),
      collectionNodeId: tabToDuplicate.collectionNodeId,
      collectionName: tabToDuplicate.collectionName,
    );
    
    final newTabs = [...state.tabs];
    newTabs.insert(index + 1, duplicatedTab);
    
    int newActiveIndex = state.activeIndex;
    if (newActiveIndex >= index + 1) {
      newActiveIndex += 1;
    }
    
    state = state.copyWith(
      tabs: newTabs,
      activeIndex: index + 1, // Focus the new tab
    );
    _scheduleSave();
  }

  void cancelRequest(int index) {
    final tab = state.tabs[index];
    final token = _cancelTokens[tab.tabId];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled request');
    }
  }

  Future<void> sendRequest() async {
    final activeTab = state.tabs[state.activeIndex];
    final config = activeTab.config;

    final cancelToken = CancelToken();
    _cancelTokens[activeTab.tabId] = cancelToken;

    updateCurrentTab(activeTab.copyWith(isSending: true));

    final stopwatch = Stopwatch()..start();
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.request(
        config.url,
        data: config.body.isNotEmpty ? config.body : null,
        queryParameters: config.params,
        options: Options(
          method: config.method,
          headers: config.headers,
        ),
        cancelToken: cancelToken,
      );

      stopwatch.stop();
      final duration = stopwatch.elapsedMilliseconds;

      String responseBody;
      if (response.data is String) {
        responseBody = response.data;
      } else {
        try {
          responseBody = json.encode(response.data);
        } catch (_) {
          responseBody = response.data.toString();
        }
      }

      final updatedTab = activeTab.copyWith(
        isSending: false,
        statusCode: response.statusCode,
        durationMs: duration,
        responseBody: responseBody,
        responseHeaders: response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      );

      _cancelTokens.remove(activeTab.tabId);
      updateCurrentTab(updatedTab);

      // Save to History
      final settings = ref.read(settingsProvider);
      HttpRequestConfig historyConfig = config.copyWith(); 
      
      if (settings.saveResponseInHistory) {
        historyConfig = historyConfig.copyWith(
          responseBody: updatedTab.responseBody,
          responseHeaders: updatedTab.responseHeaders,
          statusCode: updatedTab.statusCode,
          durationMs: updatedTab.durationMs,
        );
      }
      
      ref.read(historyProvider.notifier).addRequest(historyConfig);
    } catch (e) {
      _cancelTokens.remove(activeTab.tabId);
      
      if (e is DioException && e.type == DioExceptionType.cancel) {
        updateCurrentTab(activeTab.copyWith(isSending: false));
        return;
      }

      stopwatch.stop();
      String errorBody = e.toString();
      int? statusCode;
      Map<String, String>? headers;

      if (e is DioException) {
        if (e.response?.data != null) {
           if (e.response!.data is String) {
             errorBody = e.response!.data;
           } else {
             try {
               errorBody = json.encode(e.response!.data);
             } catch (_) {
               errorBody = e.response!.data.toString();
             }
           }
        } else {
          errorBody = e.message ?? e.toString();
        }
        statusCode = e.response?.statusCode;
        headers = e.response?.headers.map.map((k, v) => MapEntry(k, v.join(', ')));
      }

      final updatedTab = activeTab.copyWith(
        isSending: false,
        statusCode: statusCode ?? 0,
        durationMs: stopwatch.elapsedMilliseconds,
        responseBody: errorBody,
        responseHeaders: headers,
      );
      updateCurrentTab(updatedTab);

      // Save failed request to history too
      final settings = ref.read(settingsProvider);
      HttpRequestConfig historyConfig = config.copyWith();
      if (settings.saveResponseInHistory) {
        historyConfig = historyConfig.copyWith(
          responseBody: updatedTab.responseBody,
          responseHeaders: updatedTab.responseHeaders,
          statusCode: updatedTab.statusCode,
          durationMs: updatedTab.durationMs,
        );
      }
      ref.read(historyProvider.notifier).addRequest(historyConfig);
    }
  }
}

final tabsProvider = StateNotifierProvider<TabsNotifier, TabsState>((ref) {
  return TabsNotifier(ref);
});

final isTabDirtyProvider = Provider.family<bool, String>((ref, tabId) {
  final tab = ref.watch(tabsProvider.select((s) => s.tabs.firstWhereOrNull((t) => t.tabId == tabId)));
  if (tab == null || tab.collectionNodeId == null) return false;

  final collections = ref.watch(collectionsProvider);
  
  HttpRequestConfig? savedConfig;
  bool find(List<CollectionNode> nodes) {
    for (var node in nodes) {
      if (node.id == tab.collectionNodeId) {
        savedConfig = node.config;
        return true;
      }
      if (find(node.children)) return true;
    }
    return false;
  }
  find(collections);

  if (savedConfig == null) return false;
  
  // Efficient comparison using overridden == operator
  return tab.config != savedConfig;
});

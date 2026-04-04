import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/request_tab.dart';
import '../models/request_config.dart';
import '../services/storage_service.dart';
import 'history_provider.dart';
import 'settings_provider.dart';

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
  final Dio _dio = Dio();

  TabsNotifier(this.ref) : super(_loadInitialState());

  static TabsState _loadInitialState() {
    final tabs = StorageService.getTabs();
    if (tabs.isEmpty) {
      return TabsState(
        tabs: [HttpRequestTabModel(config: HttpRequestConfig(url: ''))],
        activeIndex: 0,
      );
    }
    return TabsState(tabs: tabs, activeIndex: 0);
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
    StorageService.saveTabs(state.tabs);
  }

  void removeTab(int index) {
    if (state.tabs.length <= 1) return;

    final newTabs = [...state.tabs]..removeAt(index);
    int newActiveIndex = state.activeIndex;
    if (newActiveIndex >= newTabs.length) {
      newActiveIndex = newTabs.length - 1;
    }
    state = state.copyWith(tabs: newTabs, activeIndex: newActiveIndex);
    StorageService.saveTabs(state.tabs);
  }

  void setActiveIndex(int index) {
    state = state.copyWith(activeIndex: index);
  }

  void updateCurrentTab(HttpRequestTabModel tab) {
    final newTabs = [...state.tabs];
    newTabs[state.activeIndex] = tab;
    state = state.copyWith(tabs: newTabs);
    StorageService.saveTabs(state.tabs);
  }

  Future<void> sendRequest() async {
    final activeTab = state.tabs[state.activeIndex];
    final config = activeTab.config;

    updateCurrentTab(activeTab.copyWith(isSending: true));

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.request(
        config.url,
        data: config.body.isNotEmpty ? config.body : null,
        queryParameters: config.params,
        options: Options(
          method: config.method,
          headers: config.headers,
        ),
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

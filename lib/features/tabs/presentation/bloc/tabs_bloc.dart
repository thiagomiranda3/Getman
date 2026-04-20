import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/request_tab_entity.dart';
import '../../domain/repositories/tabs_repository.dart';
import '../../../history/domain/entities/request_config_entity.dart';
import '../../../history/domain/usecases/history_usecases.dart';
import '../../../settings/domain/usecases/settings_usecases.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/network_service.dart';
import 'tabs_event.dart';
import 'tabs_state.dart';

class _RequestManager {
  final Map<String, NetworkCancelHandle> _handles = {};

  NetworkCancelHandle start(String tabId) {
    final handle = NetworkCancelHandle();
    _handles[tabId] = handle;
    return handle;
  }

  void finish(String tabId) => _handles.remove(tabId);

  void cancel(String tabId) {
    final handle = _handles[tabId];
    if (handle != null && !handle.isCancelled) {
      handle.cancel('User cancelled request');
    }
  }
}

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository repository;
  final NetworkService networkService;
  final AddToHistoryUseCase addToHistoryUseCase;
  final GetSettingsUseCase getSettingsUseCase;

  final _RequestManager _requests = _RequestManager();
  Timer? _debounceTimer;
  final Uuid uuid = const Uuid();

  static const _saveDebounce = Duration(seconds: 10);

  TabsBloc({
    required this.repository,
    required this.networkService,
    required this.addToHistoryUseCase,
    required this.getSettingsUseCase,
  }) : super(const TabsState()) {
    on<LoadTabs>(_onLoadTabs);
    on<AddTab>(_onAddTab);
    on<RemoveTab>(_onRemoveTab);
    on<SetActiveIndex>(_onSetActiveIndex);
    on<ReorderTabs>(_onReorderTabs);
    on<UpdateTab>(_onUpdateTab);
    on<CloseOtherTabs>(_onCloseOtherTabs);
    on<CloseTabsToTheRight>(_onCloseTabsToTheRight);
    on<DuplicateTab>(_onDuplicateTab);
    on<SendRequest>(_onSendRequest);
    on<CancelRequest>(_onCancelRequest);
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_saveDebounce, _persist);
  }

  Future<void> _persist() async {
    try {
      await repository.saveTabs(state.tabs);
    } on PersistenceFailure catch (f) {
      debugPrint('Tab save failed: ${f.message}');
    }
  }

  @override
  Future<void> close() async {
    _debounceTimer?.cancel();
    await _persist();
    return super.close();
  }

  Future<void> _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final tabs = await repository.getTabs();
      if (tabs.isEmpty) {
        emit(state.copyWith(
          tabs: [HttpRequestTabEntity(
            tabId: uuid.v4(),
            config: const HttpRequestConfigEntity(id: 'initial', url: ''),
          )],
          activeIndex: 0,
          isLoading: false,
        ));
      } else {
        emit(state.copyWith(tabs: tabs, activeIndex: 0, isLoading: false));
      }
    } on PersistenceFailure catch (f) {
      debugPrint('LoadTabs failed: ${f.message}');
      emit(state.copyWith(isLoading: false));
    }
  }

  void _onAddTab(AddTab event, Emitter<TabsState> emit) {
    if (event.collectionNodeId != null) {
      final existingIndex = state.tabs.indexWhere((t) => t.collectionNodeId == event.collectionNodeId);
      if (existingIndex != -1) {
        emit(state.copyWith(activeIndex: existingIndex));
        return;
      }
    }

    final newTab = HttpRequestTabEntity(
      tabId: uuid.v4(),
      config: event.config ?? HttpRequestConfigEntity(id: uuid.v4()),
      collectionNodeId: event.collectionNodeId,
      collectionName: event.collectionName,
    );

    emit(state.copyWith(
      tabs: [...state.tabs, newTab],
      activeIndex: state.tabs.length,
    ));
    _scheduleSave();
  }

  void _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) {
    final newTabs = [...state.tabs]..removeAt(event.index);
    int newActiveIndex = state.activeIndex;
    if (newTabs.isEmpty) {
      newActiveIndex = -1;
    } else if (newActiveIndex >= newTabs.length) {
      newActiveIndex = newTabs.length - 1;
    }
    emit(state.copyWith(tabs: newTabs, activeIndex: newActiveIndex));
    _scheduleSave();
  }

  void _onSetActiveIndex(SetActiveIndex event, Emitter<TabsState> emit) {
    emit(state.copyWith(activeIndex: event.index));
  }

  void _onReorderTabs(ReorderTabs event, Emitter<TabsState> emit) {
    final tabs = [...state.tabs];
    int oldIndex = event.oldIndex;
    int newIndex = event.newIndex;
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

    emit(state.copyWith(tabs: tabs, activeIndex: newActiveIndex));
    _scheduleSave();
  }

  void _onUpdateTab(UpdateTab event, Emitter<TabsState> emit) {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tab.tabId);
    if (index == -1) return;

    final newTabs = [...state.tabs];
    newTabs[index] = event.tab;
    emit(state.copyWith(tabs: newTabs));
    _scheduleSave();
  }

  void _onCloseOtherTabs(CloseOtherTabs event, Emitter<TabsState> emit) {
    if (state.tabs.length <= 1) return;
    final tabToKeep = state.tabs[event.index];
    emit(state.copyWith(
      tabs: [tabToKeep],
      activeIndex: 0,
    ));
    _scheduleSave();
  }

  void _onCloseTabsToTheRight(CloseTabsToTheRight event, Emitter<TabsState> emit) {
    if (event.index >= state.tabs.length - 1) return;
    final newTabs = state.tabs.sublist(0, event.index + 1);
    int newActiveIndex = state.activeIndex;
    if (newActiveIndex > event.index) {
      newActiveIndex = event.index;
    }
    emit(state.copyWith(
      tabs: newTabs,
      activeIndex: newActiveIndex,
    ));
    _scheduleSave();
  }

  void _onDuplicateTab(DuplicateTab event, Emitter<TabsState> emit) {
    final tabToDuplicate = state.tabs[event.index];
    final duplicatedTab = HttpRequestTabEntity(
      tabId: uuid.v4(),
      config: tabToDuplicate.config.copyWith(),
      collectionNodeId: null,
      collectionName: null,
    );

    final newTabs = [...state.tabs];
    newTabs.insert(event.index + 1, duplicatedTab);

    int newActiveIndex = state.activeIndex;
    if (newActiveIndex >= event.index + 1) {
      newActiveIndex += 1;
    }

    emit(state.copyWith(
      tabs: newTabs,
      activeIndex: event.index + 1,
    ));
    _scheduleSave();
  }

  Future<void> _onSendRequest(SendRequest event, Emitter<TabsState> emit) async {
    final activeIndex = state.activeIndex;
    if (activeIndex < 0 || activeIndex >= state.tabs.length) return;

    final activeTab = state.tabs[activeIndex];
    final config = activeTab.config;
    final handle = _requests.start(activeTab.tabId);

    final sendingTab = activeTab.copyWith(isSending: true);
    emit(state.copyWith(tabs: _replaceTab(state.tabs, activeIndex, sendingTab)));

    try {
      final response = await networkService.request(
        url: config.url,
        method: config.method,
        data: config.body.isNotEmpty ? config.body : null,
        queryParameters: config.params,
        headers: config.headers,
        cancelHandle: handle,
      );
      _requests.finish(activeTab.tabId);

      final updatedTab = sendingTab.copyWith(
        isSending: false,
        statusCode: response.statusCode,
        durationMs: response.durationMs,
        responseBody: response.body,
        responseHeaders: response.headers,
      );
      emit(state.copyWith(tabs: _replaceTabById(state.tabs, updatedTab)));

      await _recordHistory(config, updatedTab);
    } on NetworkFailure catch (f) {
      _requests.finish(activeTab.tabId);

      if (f.type == NetworkFailureType.cancelled) {
        emit(state.copyWith(tabs: _replaceTabById(state.tabs, activeTab.copyWith(isSending: false))));
        return;
      }

      final updatedTab = activeTab.copyWith(
        isSending: false,
        statusCode: f.statusCode ?? 0,
        durationMs: 0,
        responseBody: f.message,
        responseHeaders: const {},
      );
      emit(state.copyWith(tabs: _replaceTabById(state.tabs, updatedTab)));
      await _recordHistory(config, updatedTab);
    }
  }

  Future<void> _recordHistory(HttpRequestConfigEntity config, HttpRequestTabEntity tab) async {
    try {
      final settings = await getSettingsUseCase();
      var historyConfig = config.copyWith();
      if (settings.saveResponseInHistory) {
        historyConfig = historyConfig.copyWith(
          responseBody: tab.responseBody,
          responseHeaders: tab.responseHeaders,
          statusCode: tab.statusCode,
          durationMs: tab.durationMs,
        );
      }
      await addToHistoryUseCase(historyConfig, settings.historyLimit);
    } catch (e) {
      debugPrint('History record failed: $e');
    }
  }

  List<HttpRequestTabEntity> _replaceTab(List<HttpRequestTabEntity> tabs, int index, HttpRequestTabEntity replacement) {
    final copy = [...tabs];
    copy[index] = replacement;
    return copy;
  }

  List<HttpRequestTabEntity> _replaceTabById(List<HttpRequestTabEntity> tabs, HttpRequestTabEntity replacement) {
    final index = tabs.indexWhere((t) => t.tabId == replacement.tabId);
    if (index == -1) return tabs;
    return _replaceTab(tabs, index, replacement);
  }

  void _onCancelRequest(CancelRequest event, Emitter<TabsState> emit) {
    if (event.index < 0 || event.index >= state.tabs.length) return;
    _requests.cancel(state.tabs[event.index].tabId);
  }
}

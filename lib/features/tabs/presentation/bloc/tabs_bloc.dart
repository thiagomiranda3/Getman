import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/request_tab_entity.dart';
import '../../domain/repositories/tabs_repository.dart';
import '../../domain/usecases/send_request_use_case.dart';
import '../../../../core/domain/entities/request_config_entity.dart';
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

  void cancel(String tabId, {String reason = 'User cancelled request'}) {
    final handle = _handles[tabId];
    if (handle != null && !handle.isCancelled) {
      handle.cancel(reason);
    }
  }

  /// Cancel the in-flight request (if any) and drop the handle.
  void cancelAndFinish(String tabId) {
    cancel(tabId);
    finish(tabId);
  }

  void cancelAll() {
    for (final handle in _handles.values) {
      if (!handle.isCancelled) handle.cancel('Bloc closed');
    }
    _handles.clear();
  }
}

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository repository;
  final SendRequestUseCase sendRequestUseCase;

  final _RequestManager _requests = _RequestManager();
  Timer? _debounceTimer;
  final Uuid uuid = const Uuid();

  static const _saveDebounce = Duration(seconds: 10);

  TabsBloc({
    required this.repository,
    required this.sendRequestUseCase,
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

  /// Cancel any pending debounced save and flush immediately. Use on structural
  /// changes (add/remove/reorder/duplicate/close-others/close-right) so the
  /// user never loses tabs if the app is quit before the 10s debounce fires.
  Future<void> _persistNow() async {
    _debounceTimer?.cancel();
    await _persist();
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
    _requests.cancelAll();
    await _persist();
    return super.close();
  }

  Future<void> _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final tabs = await repository.getTabs();
      if (tabs.isEmpty) {
        final newTabId = uuid.v4();
        emit(state.copyWith(
          tabs: [HttpRequestTabEntity(
            tabId: newTabId,
            config: HttpRequestConfigEntity(id: newTabId, url: ''),
          )],
          activeIndex: 0,
          isLoading: false,
        ));
      } else {
        // Reset transient in-flight flags — there is no live request after a restart.
        final sanitized = tabs.map((t) => t.isSending ? t.copyWith(isSending: false) : t).toList();
        emit(state.copyWith(tabs: sanitized, activeIndex: 0, isLoading: false));
      }
    } on PersistenceFailure catch (f) {
      debugPrint('LoadTabs failed: ${f.message}');
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onAddTab(AddTab event, Emitter<TabsState> emit) async {
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
    await _persistNow();
  }

  Future<void> _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1) return;
    _requests.cancelAndFinish(event.tabId);

    final newTabs = [...state.tabs]..removeAt(index);
    int newActiveIndex = state.activeIndex;
    if (newTabs.isEmpty) {
      newActiveIndex = -1;
    } else if (newActiveIndex >= newTabs.length) {
      newActiveIndex = newTabs.length - 1;
    }
    emit(state.copyWith(tabs: newTabs, activeIndex: newActiveIndex));
    await _persistNow();
  }

  void _onSetActiveIndex(SetActiveIndex event, Emitter<TabsState> emit) {
    emit(state.copyWith(activeIndex: event.index));
  }

  Future<void> _onReorderTabs(ReorderTabs event, Emitter<TabsState> emit) async {
    final tabs = [...state.tabs];
    final oldIndex = event.oldIndex;
    var newIndex = event.newIndex;
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
    await _persistNow();
  }

  void _onUpdateTab(UpdateTab event, Emitter<TabsState> emit) {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tab.tabId);
    if (index == -1) return;

    final newTabs = [...state.tabs];
    newTabs[index] = event.tab;
    emit(state.copyWith(tabs: newTabs));
    _scheduleSave();
  }

  Future<void> _onCloseOtherTabs(CloseOtherTabs event, Emitter<TabsState> emit) async {
    if (state.tabs.length <= 1) return;
    final tabToKeep = state.tabs.byId(event.tabId);
    if (tabToKeep == null) return;
    emit(state.copyWith(
      tabs: [tabToKeep],
      activeIndex: 0,
    ));
    await _persistNow();
  }

  Future<void> _onCloseTabsToTheRight(CloseTabsToTheRight event, Emitter<TabsState> emit) async {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1 || index >= state.tabs.length - 1) return;
    final newTabs = state.tabs.sublist(0, index + 1);
    int newActiveIndex = state.activeIndex;
    if (newActiveIndex > index) {
      newActiveIndex = index;
    }
    emit(state.copyWith(
      tabs: newTabs,
      activeIndex: newActiveIndex,
    ));
    await _persistNow();
  }

  Future<void> _onDuplicateTab(DuplicateTab event, Emitter<TabsState> emit) async {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1) return;
    final tabToDuplicate = state.tabs[index];
    final duplicatedTab = HttpRequestTabEntity(
      tabId: uuid.v4(),
      config: tabToDuplicate.config.copyWith(),
      collectionNodeId: null,
      collectionName: null,
    );

    final newTabs = [...state.tabs];
    newTabs.insert(index + 1, duplicatedTab);

    int newActiveIndex = state.activeIndex;
    if (newActiveIndex >= index + 1) {
      newActiveIndex += 1;
    }

    emit(state.copyWith(
      tabs: newTabs,
      activeIndex: index + 1,
    ));
    await _persistNow();
  }

  Future<void> _onSendRequest(SendRequest event, Emitter<TabsState> emit) async {
    final activeIndex = state.activeIndex;
    if (activeIndex < 0 || activeIndex >= state.tabs.length) return;

    final activeTab = state.tabs[activeIndex];
    final tabId = activeTab.tabId;
    final config = activeTab.config;
    final handle = _requests.start(tabId);

    emit(state.copyWith(tabs: _replaceTabById(state.tabs, activeTab.copyWith(isSending: true))));

    try {
      final response = await sendRequestUseCase(
        config: config,
        envVars: event.envVars,
        cancelHandle: handle,
      );
      _requests.finish(tabId);
      _applyToTab(emit, tabId, (live) => live.copyWith(
        isSending: false,
        statusCode: response.statusCode,
        durationMs: response.durationMs,
        responseBody: response.body,
        responseHeaders: response.headers,
      ));
    } on NetworkFailure catch (f) {
      _requests.finish(tabId);

      if (f.type == NetworkFailureType.cancelled) {
        _applyToTab(emit, tabId, (live) => live.copyWith(isSending: false));
        return;
      }

      _applyToTab(emit, tabId, (live) => live.copyWith(
        isSending: false,
        statusCode: f.statusCode ?? 0,
        durationMs: 0,
        responseBody: f.message,
        responseHeaders: const <String, String>{},
      ));
    }
  }

  /// Resolve [tabId] against the latest state and emit a new state with the
  /// transformed tab. No-op if the tab has been closed while the request ran.
  void _applyToTab(
    Emitter<TabsState> emit,
    String tabId,
    HttpRequestTabEntity Function(HttpRequestTabEntity live) transform,
  ) {
    final live = state.tabs.byId(tabId);
    if (live == null) return;
    emit(state.copyWith(tabs: _replaceTabById(state.tabs, transform(live))));
  }

  List<HttpRequestTabEntity> _replaceTabById(List<HttpRequestTabEntity> tabs, HttpRequestTabEntity replacement) {
    final index = tabs.indexWhere((t) => t.tabId == replacement.tabId);
    if (index == -1) return tabs;
    final copy = [...tabs];
    copy[index] = replacement;
    return copy;
  }

  void _onCancelRequest(CancelRequest event, Emitter<TabsState> emit) {
    _requests.cancel(event.tabId);
  }
}

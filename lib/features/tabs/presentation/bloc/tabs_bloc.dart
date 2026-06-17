import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
// Imported only for `compute` (evaluates rules off the UI isolate for large
// bodies). There is no Flutter-free equivalent — Isolate.run is unsupported on
// web, which this app targets — so this import must stay.
// ignore: avoid_flutter_imports
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/perf_trace.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/logic/rules_runner.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/request_manager.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:uuid/uuid.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  TabsBloc({
    required TabsRepository repository,
    required SendRequestUseCase sendRequestUseCase,
    GetRequestRulesUseCase? getRequestRulesUseCase,
  }) : _repository = repository,
       _sendRequestUseCase = sendRequestUseCase,
       _getRequestRulesUseCase = getRequestRulesUseCase,
       super(const TabsState()) {
    on<LoadTabs>(_onLoadTabs);
    on<AddTab>(_onAddTab);
    on<RemoveTab>(_onRemoveTab);
    on<SetActiveIndex>(_onSetActiveIndex);
    on<ReorderTabs>(_onReorderTabs);
    on<UpdateTab>(_onUpdateTab);
    on<CloseOtherTabs>(_onCloseOtherTabs);
    on<CloseTabsToTheRight>(_onCloseTabsToTheRight);
    on<CloseTabsToTheLeft>(_onCloseTabsToTheLeft);
    on<DuplicateTab>(_onDuplicateTab);
    on<SendRequest>(_onSendRequest);
    on<ViewResponseHistoryEntry>(_onViewResponseHistoryEntry);
    on<CancelRequest>(_onCancelRequest);
  }
  final TabsRepository _repository;
  final SendRequestUseCase _sendRequestUseCase;

  /// Optional: when provided, post-response extraction + assertions run after
  /// each send. Nullable so tests can construct the bloc without it.
  final GetRequestRulesUseCase? _getRequestRulesUseCase;

  final RequestManager _requests = RequestManager();

  /// Tabs edited since the last flush. The debounce timer persists only these
  /// (via `putTab`), never the whole list — full rewrites serialize every
  /// cached response body on the UI isolate (see persistence_limits.dart).
  final Set<String> _dirtyTabIds = {};
  Timer? _debounceTimer;
  static const Uuid _uuid = Uuid();

  static const _saveDebounce = Duration(seconds: 10);

  /// Bodies at or below this run the post-response rules inline; larger bodies
  /// decode + evaluate on a background isolate (`compute`). The threshold sits
  /// well above isolate-spawn overhead so small responses don't pay it.
  static const int _ruleComputeThresholdBytes = 64 * 1024;

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_saveDebounce, _flushDirtyTabs);
  }

  /// Persist every dirty tab still alive in [state] via `putTab`. Iterates a
  /// snapshot and removes each id just before its write: an edit landing
  /// mid-flush re-dirties the id (instead of being swallowed by a wholesale
  /// clear), and a failed write re-adds it so the next debounce retries.
  Future<void> _flushDirtyTabs() async {
    if (_dirtyTabIds.isEmpty) return;
    final pending = _dirtyTabIds.toList(growable: false);
    for (final id in pending) {
      _dirtyTabIds.remove(id);
      final tab = state.tabs.byId(id);
      if (tab == null) continue;
      try {
        await traceAsync('tabs.putTab', () => _repository.putTab(tab));
      } on PersistenceFailure catch (f) {
        _dirtyTabIds.add(id);
        log('Tab save failed: ${f.message}', name: 'TabsBloc');
      }
    }
  }

  Future<void> _persistOrder() async {
    try {
      await _repository.saveTabOrder(
        state.tabs.map((t) => t.tabId).toList(growable: false),
      );
    } on PersistenceFailure catch (f) {
      log('Tab order save failed: ${f.message}', name: 'TabsBloc');
    }
  }

  /// Run a structural write (putTab/deleteTabs/saveTabOrder). UI state is
  /// already emitted and must never be blocked or reverted by a failed write —
  /// failures are logged, matching the debounce path.
  Future<void> _guardWrite(Future<void> Function() write) async {
    try {
      await write();
    } on PersistenceFailure catch (f) {
      log('Tab save failed: ${f.message}', name: 'TabsBloc');
    }
  }

  @override
  Future<void> close() async {
    _debounceTimer?.cancel();
    _requests.cancelAll();
    // Flush pending edits incrementally — no full saveTabs rewrite on quit.
    await _flushDirtyTabs();
    await _persistOrder();
    return super.close();
  }

  Future<void> _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final tabs = await _repository.getTabs();
      if (tabs.isEmpty) {
        // First run (nothing persisted): seed a working sample request so the
        // user can hit SEND immediately rather than facing a blank URL bar.
        final newTabId = _uuid.v4();
        final newTab = HttpRequestTabEntity(
          tabId: newTabId,
          config: HttpRequestConfigEntity(
            id: newTabId,
            url: 'https://httpbin.org/get',
          ),
        );
        emit(
          state.copyWith(
            tabs: [newTab],
            activeIndex: 0,
            isLoading: false,
          ),
        );
        // Persist the fresh tab + order so a clean boot is consistent on disk.
        await _guardWrite(() => _repository.putTab(newTab));
        await _persistOrder();
      } else {
        // Reset transient in-flight flags — there is no live request after a
        // restart.
        final sanitized = tabs
            .map((t) => t.isSending ? t.copyWith(isSending: false) : t)
            .toList();
        emit(state.copyWith(tabs: sanitized, activeIndex: 0, isLoading: false));
      }
    } on PersistenceFailure catch (f) {
      log('LoadTabs failed: ${f.message}', name: 'TabsBloc');
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onAddTab(AddTab event, Emitter<TabsState> emit) async {
    if (event.collectionNodeId != null) {
      final existingIndex = state.tabs.indexWhere(
        (t) => t.collectionNodeId == event.collectionNodeId,
      );
      if (existingIndex != -1) {
        emit(state.copyWith(activeIndex: existingIndex));
        return;
      }
    }

    final newTab = HttpRequestTabEntity(
      tabId: _uuid.v4(),
      config: event.config ?? HttpRequestConfigEntity(id: _uuid.v4()),
      collectionNodeId: event.collectionNodeId,
      collectionName: event.collectionName,
      response: event.response,
    );

    emit(
      state.copyWith(
        tabs: [...state.tabs, newTab],
        activeIndex: state.tabs.length,
      ),
    );
    await _guardWrite(() => _repository.putTab(newTab));
    await _persistOrder();
  }

  Future<void> _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1) return;
    _requests.cancelAndFinish(event.tabId);

    final newTabs = [...state.tabs]..removeAt(index);
    var newActiveIndex = state.activeIndex;
    if (newTabs.isEmpty) {
      newActiveIndex = -1;
    } else if (newActiveIndex >= newTabs.length) {
      newActiveIndex = newTabs.length - 1;
    }
    emit(state.copyWith(tabs: newTabs, activeIndex: newActiveIndex));
    _dirtyTabIds.remove(event.tabId);
    await _guardWrite(() => _repository.deleteTabs([event.tabId]));
    await _persistOrder();
  }

  void _onSetActiveIndex(SetActiveIndex event, Emitter<TabsState> emit) {
    // Reject out-of-range indices (e.g. from a stale sheet/menu context) so
    // widgets can index `tabs[activeIndex]` without re-checking bounds.
    if (event.index < 0 || event.index >= state.tabs.length) return;
    emit(state.copyWith(activeIndex: event.index));
  }

  Future<void> _onReorderTabs(
    ReorderTabs event,
    Emitter<TabsState> emit,
  ) async {
    final tabs = [...state.tabs];
    final oldIndex = event.oldIndex;
    var newIndex = event.newIndex;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, item);

    var newActiveIndex = state.activeIndex;
    if (oldIndex == state.activeIndex) {
      newActiveIndex = newIndex;
    } else if (oldIndex < state.activeIndex && newIndex >= state.activeIndex) {
      newActiveIndex -= 1;
    } else if (oldIndex > state.activeIndex && newIndex <= state.activeIndex) {
      newActiveIndex += 1;
    }

    emit(state.copyWith(tabs: tabs, activeIndex: newActiveIndex));
    // Reordering changes no tab payloads — only the order list.
    await _persistOrder();
  }

  void _onUpdateTab(UpdateTab event, Emitter<TabsState> emit) {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tab.tabId);
    if (index == -1) return;

    final newTabs = [...state.tabs];
    newTabs[index] = event.tab;
    emit(state.copyWith(tabs: newTabs));
    _dirtyTabIds.add(event.tab.tabId);
    _scheduleSave();
  }

  Future<void> _onCloseOtherTabs(
    CloseOtherTabs event,
    Emitter<TabsState> emit,
  ) async {
    if (state.tabs.length <= 1) return;
    final tabToKeep = state.tabs.byId(event.tabId);
    if (tabToKeep == null) return;
    final removedIds = state.tabs
        .where((t) => t.tabId != event.tabId)
        .map((t) => t.tabId)
        .toList(growable: false);
    emit(
      state.copyWith(
        tabs: [tabToKeep],
        activeIndex: 0,
      ),
    );
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistOrder();
  }

  Future<void> _onCloseTabsToTheRight(
    CloseTabsToTheRight event,
    Emitter<TabsState> emit,
  ) async {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1 || index >= state.tabs.length - 1) return;
    final newTabs = state.tabs.sublist(0, index + 1);
    final removedIds = state.tabs
        .sublist(index + 1)
        .map((t) => t.tabId)
        .toList(growable: false);
    var newActiveIndex = state.activeIndex;
    if (newActiveIndex > index) {
      newActiveIndex = index;
    }
    emit(
      state.copyWith(
        tabs: newTabs,
        activeIndex: newActiveIndex,
      ),
    );
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistOrder();
  }

  Future<void> _onCloseTabsToTheLeft(
    CloseTabsToTheLeft event,
    Emitter<TabsState> emit,
  ) async {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index <= 0) return;
    final newTabs = state.tabs.sublist(index);
    final removedIds = state.tabs
        .sublist(0, index)
        .map((t) => t.tabId)
        .toList(growable: false);
    // Every kept tab shifts left by `index` positions, so move the active
    // index by the same amount; clamp to 0 if it pointed at a removed tab.
    final newActiveIndex = (state.activeIndex - index).clamp(0, newTabs.length);
    emit(
      state.copyWith(
        tabs: newTabs,
        activeIndex: newActiveIndex,
      ),
    );
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistOrder();
  }

  Future<void> _onDuplicateTab(
    DuplicateTab event,
    Emitter<TabsState> emit,
  ) async {
    final index = state.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1) return;
    final tabToDuplicate = state.tabs[index];
    final duplicatedTab = HttpRequestTabEntity(
      tabId: _uuid.v4(),
      config: tabToDuplicate.config.copyWith(),
    );

    final newTabs = [...state.tabs]..insert(index + 1, duplicatedTab);

    var newActiveIndex = state.activeIndex;
    if (newActiveIndex >= index + 1) {
      newActiveIndex += 1;
    }

    emit(
      state.copyWith(
        tabs: newTabs,
        activeIndex: index + 1,
      ),
    );
    await _guardWrite(() => _repository.putTab(duplicatedTab));
    await _persistOrder();
  }

  Future<void> _onSendRequest(
    SendRequest event,
    Emitter<TabsState> emit,
  ) async {
    final tab = state.tabs.byId(event.tabId);
    if (tab == null || tab.isSending) return;

    final tabId = tab.tabId;
    final config = tab.config;
    final handle = _requests.start(tabId);

    // Clear the previous run's rule results when a new send starts.
    emit(
      state.copyWith(
        tabs: _replaceTabById(
          state.tabs,
          tab.copyWith(
            isSending: true,
            extractionResults: const [],
            assertionResults: const [],
          ),
        ),
      ),
    );

    try {
      final response = await _sendRequestUseCase(
        config: config,
        envVars: event.envVars,
        cancelHandle: handle,
      );
      _requests.finish(tabId);
      _applyToTab(
        emit,
        tabId,
        (live) => _recordResponse(
          live,
          response,
          event.responseHistoryLimit,
          saveLarge: event.saveLargeResponsesInHistory,
        ),
      );
      _markResponseDirty(tabId);
      await _applyRules(emit, tabId, config, response);
    } on NetworkFailure catch (f) {
      _requests.finish(tabId);

      if (f.type == NetworkFailureType.cancelled) {
        _applyToTab(emit, tabId, (live) => live.copyWith(isSending: false));
        return;
      }

      final errorResponse = HttpResponseEntity(
        statusCode: f.statusCode ?? 0,
        body: f.message,
        headers: const {},
        durationMs: 0,
      );
      _applyToTab(
        emit,
        tabId,
        (live) => _recordResponse(
          live,
          errorResponse,
          event.responseHistoryLimit,
          saveLarge: event.saveLargeResponsesInHistory,
        ),
      );
      _markResponseDirty(tabId);
      // Assertions are meaningful on error responses too
      // (e.g. "status in 2xx").
      await _applyRules(emit, tabId, config, errorResponse);
    } on Object catch (e) {
      // Anything unexpected must still release the tab — otherwise it is
      // stuck on "SENDING" with no way to retry or cancel.
      _requests.finish(tabId);
      log('SendRequest failed unexpectedly: $e', name: 'TabsBloc');
      _applyToTab(emit, tabId, (live) => live.copyWith(isSending: false));
    }
  }

  /// Sets [response] as the tab's displayed response and prepends it to the
  /// time-travel history (newest-first), trimmed to [limit]. A [limit] of 0
  /// disables history (clears any accumulated entries). When [saveLarge] is
  /// false, a history entry whose body exceeds the large-viewer threshold is
  /// stored as a placeholder (the displayed [response] still keeps the full
  /// body); on-disk capping at 1 MiB happens at the persistence boundary.
  HttpRequestTabEntity _recordResponse(
    HttpRequestTabEntity live,
    HttpResponseEntity response,
    int limit, {
    required bool saveLarge,
  }) {
    if (limit <= 0) {
      return live.copyWith(
        isSending: false,
        response: response,
        responseHistory: const [],
      );
    }
    final stored =
        !saveLarge && response.body.length > kLargeResponseViewerChars
        ? response.copyWithBody(kResponseBodyTooLargePlaceholder)
        : response;
    final entry = ResponseHistoryEntry(
      id: _uuid.v4(),
      response: stored,
      capturedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final history = [entry, ...live.responseHistory];
    return live.copyWith(
      isSending: false,
      response: response,
      responseHistory: history.length > limit
          ? history.sublist(0, limit)
          : history,
    );
  }

  /// Time-travel: swap the displayed response to the chosen history entry
  /// without mutating the history. No-op if the tab or entry is gone.
  void _onViewResponseHistoryEntry(
    ViewResponseHistoryEntry event,
    Emitter<TabsState> emit,
  ) {
    final tab = state.tabs.byId(event.tabId);
    if (tab == null) return;
    final entry = tab.responseHistory.firstWhereOrNull(
      (e) => e.id == event.entryId,
    );
    if (entry == null) return;
    emit(
      state.copyWith(
        tabs: _replaceTabById(
          state.tabs,
          tab.copyWith(response: entry.response),
        ),
      ),
    );
    _markResponseDirty(event.tabId);
  }

  /// Schedule a debounced persist for the tab that just received a response
  /// (or error response) so cached responses survive a restart. No-op when the
  /// tab was closed while the request ran.
  void _markResponseDirty(String tabId) {
    if (state.tabs.byId(tabId) == null) return;
    _dirtyTabIds.add(tabId);
    _scheduleSave();
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

  /// Loads the request's rules and runs the extraction + assertion engines
  /// against [response], stashing the (transient) results on the tab. No-op
  /// when no rules use case is wired or the request has no rules. The captured
  /// values are written back to the environment by a widget-layer coordinator.
  Future<void> _applyRules(
    Emitter<TabsState> emit,
    String tabId,
    HttpRequestConfigEntity config,
    HttpResponseEntity response,
  ) async {
    final useCase = _getRequestRulesUseCase;
    if (useCase == null) return;
    RequestRulesEntity rules;
    try {
      rules = await useCase(config.id);
    } on Failure catch (f) {
      log('Loading rules failed: $f', name: 'TabsBloc');
      return;
    }
    if (rules.isEmpty) return;
    final input = RulesRunInput(
      extractionRules: rules.extractionRules,
      assertions: rules.assertions,
      response: response,
    );
    // Decode + evaluate once; off the UI isolate for large bodies.
    // `_applyToTab` re-resolves the tab after the await, so a closed/replaced
    // tab is a no-op.
    final output = response.body.length <= _ruleComputeThresholdBytes
        ? traceSync('rules.run', () => runRules(input))
        : await traceAsync('rules.run.isolate', () => compute(runRules, input));
    _applyToTab(
      emit,
      tabId,
      (live) => live.copyWith(
        extractionResults: output.extraction,
        assertionResults: output.assertions,
      ),
    );
  }

  List<HttpRequestTabEntity> _replaceTabById(
    List<HttpRequestTabEntity> tabs,
    HttpRequestTabEntity replacement,
  ) {
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

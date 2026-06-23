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
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
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
    on<AddPanel>(_onAddPanel);
    on<RemovePanel>(_onRemovePanel);
    on<RenamePanel>(_onRenamePanel);
    on<SetActivePanel>(_onSetActivePanel);
    on<ReorderPanels>(_onReorderPanels);
    on<MoveTabToPanel>(_onMoveTabToPanel);
    on<MoveTabToNewPanel>(_onMoveTabToNewPanel);
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
      final tab = _findTab(id);
      if (tab == null) continue;
      try {
        await traceAsync('tabs.putTab', () => _repository.putTab(tab));
      } on PersistenceFailure catch (f) {
        _dirtyTabIds.add(id);
        log('Tab save failed: ${f.message}', name: 'TabsBloc');
      }
    }
  }

  /// Run a structural write (putTab/deleteTabs/putPanel/...). UI state is
  /// already emitted and must never be blocked or reverted by a failed write —
  /// failures are logged, matching the debounce path.
  Future<void> _guardWrite(Future<void> Function() write) async {
    try {
      await write();
    } on PersistenceFailure catch (f) {
      log('Tab save failed: ${f.message}', name: 'TabsBloc');
    }
  }

  // --- Panel helpers -------------------------------------------------------

  PanelEntity get _activePanel =>
      state.panels.byId(state.activePanelId) ?? state.panels.first;

  Iterable<HttpRequestTabEntity> get _allTabs =>
      state.panels.expand((p) => p.tabs);

  HttpRequestTabEntity? _findTab(String tabId) => _allTabs.byId(tabId);

  /// Recompute the derived active-panel view (tabs/activeIndex) from panels.
  TabsState _derive(
    List<PanelEntity> panels,
    String activePanelId, {
    bool? isLoading,
  }) {
    final active =
        panels.byId(activePanelId) ?? (panels.isNotEmpty ? panels.first : null);
    final tabs = active?.tabs ?? const <HttpRequestTabEntity>[];
    final idx = active == null
        ? 0
        : tabs.indexWhere((t) => t.tabId == active.activeTabId);
    return TabsState(
      panels: panels,
      activePanelId: active?.id ?? '',
      tabs: tabs,
      activeIndex: idx < 0 ? 0 : idx,
      isLoading: isLoading ?? state.isLoading,
    );
  }

  List<PanelEntity> _replacePanel(
    List<PanelEntity> panels,
    PanelEntity replacement,
  ) {
    final i = panels.indexWhere((p) => p.id == replacement.id);
    if (i == -1) return panels;
    final copy = [...panels];
    copy[i] = replacement;
    return copy;
  }

  /// Replace a tab wherever it lives (in-flight sends, update, time-travel —
  /// the owning panel may not be the active one).
  List<PanelEntity> _replaceTabAcrossPanels(HttpRequestTabEntity replacement) {
    return state.panels.map((p) {
      final i = p.tabs.indexWhere((t) => t.tabId == replacement.tabId);
      if (i == -1) return p;
      final tabs = [...p.tabs];
      tabs[i] = replacement;
      return p.copyWith(tabs: tabs);
    }).toList();
  }

  String _nextPanelName() => _nextPanelNameExcluding(null);

  /// Returns the first "Panel N" name not in use, optionally ignoring the panel
  /// with [excludeId] (used when a rename-to-empty wants to reclaim the panel's
  /// own slot — e.g. "Panel 1" renamed to "" resets to "Panel 1" rather than
  /// skipping to "Panel 2").
  String _nextPanelNameExcluding(String? excludeId) {
    final used = state.panels
        .where((p) => p.id != excludeId)
        .map((p) => p.name)
        .toSet();
    var n = 1;
    while (used.contains('Panel $n')) {
      n++;
    }
    return 'Panel $n';
  }

  Future<void> _persistPanel(PanelEntity panel) =>
      _guardWrite(() => _repository.putPanel(panel));

  Future<void> _persistPanelMeta() => _guardWrite(
    () => _repository.savePanelMeta(
      state.panels.map((p) => p.id).toList(),
      state.activePanelId,
    ),
  );

  @override
  Future<void> close() async {
    _debounceTimer?.cancel();
    _requests.cancelAll();
    await _flushDirtyTabs();
    for (final p in state.panels) {
      await _persistPanel(p);
    }
    await _persistPanelMeta();
    return super.close();
  }

  Future<void> _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      var panels = await _repository.getPanels();
      final storedActive = await _repository.getActivePanelId();

      if (panels.isEmpty) {
        // True first run: seed "Panel 1" with a working sample request.
        final tabId = _uuid.v4();
        final panelId = _uuid.v4();
        final seed = PanelEntity(
          id: panelId,
          name: 'Panel 1',
          tabs: [
            HttpRequestTabEntity(
              tabId: tabId,
              config: HttpRequestConfigEntity(
                id: tabId,
                url: 'https://httpbin.org/get',
              ),
            ),
          ],
          activeTabId: tabId,
        );
        emit(_derive([seed], panelId, isLoading: false));
        await _guardWrite(() => _repository.putTab(seed.tabs.first));
        await _persistPanel(seed);
        await _persistPanelMeta();
        return;
      }

      // Sanitize transient flags. Panels may be empty (a workspace the user
      // closed every tab in) — they round-trip empty, never re-seeded.
      panels = panels
          .map(
            (p) => p.copyWith(
              tabs: p.tabs
                  .map((t) => t.isSending ? t.copyWith(isSending: false) : t)
                  .toList(),
            ),
          )
          .toList();

      final activeId =
          (storedActive != null && panels.byId(storedActive) != null)
          ? storedActive
          : panels.first.id;
      emit(_derive(panels, activeId, isLoading: false));

      // If meta was absent, we just migrated from the legacy layout — persist
      // the assembled panels so the next launch reads from the panels box.
      if (storedActive == null) {
        for (final p in panels) {
          await _persistPanel(p);
        }
        await _persistPanelMeta();
      }
    } on PersistenceFailure catch (f) {
      log('LoadTabs failed: ${f.message}', name: 'TabsBloc');
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onAddTab(AddTab event, Emitter<TabsState> emit) async {
    if (state.panels.isEmpty) return;
    // Global dedup: if a tab for this node is already open in any panel, switch
    // to it instead of opening a duplicate.
    if (event.collectionNodeId != null) {
      for (final p in state.panels) {
        final existing = p.tabs.firstWhereOrNull(
          (t) => t.collectionNodeId == event.collectionNodeId,
        );
        if (existing != null) {
          final updated = p.copyWith(activeTabId: existing.tabId);
          emit(_derive(_replacePanel(state.panels, updated), p.id));
          await _persistPanel(updated);
          await _persistPanelMeta();
          return;
        }
      }
    }

    final newTab = HttpRequestTabEntity(
      tabId: _uuid.v4(),
      config: event.config ?? HttpRequestConfigEntity(id: _uuid.v4()),
      collectionNodeId: event.collectionNodeId,
      collectionName: event.collectionName,
      response: event.response,
    );
    final active = _activePanel;
    final updated = active.copyWith(
      tabs: [...active.tabs, newTab],
      activeTabId: newTab.tabId,
    );
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _guardWrite(() => _repository.putTab(newTab));
    await _persistPanel(updated);
  }

  Future<void> _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final owner = state.panels.firstWhereOrNull(
      (p) => p.tabs.any((t) => t.tabId == event.tabId),
    );
    if (owner == null) return;
    _requests.cancelAndFinish(event.tabId);

    final removedIdx = owner.tabs.indexWhere((t) => t.tabId == event.tabId);
    final remaining = [...owner.tabs]..removeAt(removedIdx);
    var updated = owner.copyWith(tabs: remaining);
    // Re-point activeTabId only when the closed tab was active. An emptied
    // panel resets it to '' (the panel shows the "NO OPEN TABS" placeholder).
    if (owner.activeTabId == event.tabId) {
      updated = updated.copyWith(
        activeTabId: remaining.isEmpty
            ? ''
            : remaining[removedIdx.clamp(0, remaining.length - 1)].tabId,
      );
    }

    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.remove(event.tabId);
    await _guardWrite(() => _repository.deleteTabs([event.tabId]));
    await _persistPanel(updated);
  }

  Future<void> _onSetActiveIndex(
    SetActiveIndex event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.isEmpty) return;
    final active = _activePanel;
    if (event.index < 0 || event.index >= active.tabs.length) return;
    final updated = active.copyWith(
      activeTabId: active.tabs[event.index].tabId,
    );
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _persistPanel(updated);
  }

  Future<void> _onReorderTabs(
    ReorderTabs event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.isEmpty) return;
    final active = _activePanel;
    final tabs = [...active.tabs];
    var newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final item = tabs.removeAt(event.oldIndex);
    tabs.insert(newIndex, item);
    final updated = active.copyWith(tabs: tabs);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _persistPanel(updated);
  }

  void _onUpdateTab(UpdateTab event, Emitter<TabsState> emit) {
    if (_findTab(event.tab.tabId) == null) return;
    emit(_derive(_replaceTabAcrossPanels(event.tab), state.activePanelId));
    _dirtyTabIds.add(event.tab.tabId);
    _scheduleSave();
  }

  Future<void> _onCloseOtherTabs(
    CloseOtherTabs event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.isEmpty) return;
    final active = _activePanel;
    if (active.tabs.length <= 1) return;
    final keep = active.tabs.byId(event.tabId);
    if (keep == null) return;
    final removedIds = active.tabs
        .where((t) => t.tabId != event.tabId)
        .map((t) => t.tabId)
        .toList(growable: false);
    final updated = active.copyWith(tabs: [keep], activeTabId: keep.tabId);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistPanel(updated);
  }

  Future<void> _onCloseTabsToTheRight(
    CloseTabsToTheRight event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.isEmpty) return;
    final active = _activePanel;
    final index = active.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1 || index >= active.tabs.length - 1) return;
    final kept = active.tabs.sublist(0, index + 1);
    final removedIds = active.tabs
        .sublist(index + 1)
        .map((t) => t.tabId)
        .toList(growable: false);
    final activeKept = kept.any((t) => t.tabId == active.activeTabId);
    final updated = active.copyWith(
      tabs: kept,
      activeTabId: activeKept ? active.activeTabId : kept.last.tabId,
    );
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistPanel(updated);
  }

  Future<void> _onCloseTabsToTheLeft(
    CloseTabsToTheLeft event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.isEmpty) return;
    final active = _activePanel;
    final index = active.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index <= 0) return;
    final kept = active.tabs.sublist(index);
    final removedIds = active.tabs
        .sublist(0, index)
        .map((t) => t.tabId)
        .toList(growable: false);
    final activeKept = kept.any((t) => t.tabId == active.activeTabId);
    final updated = active.copyWith(
      tabs: kept,
      activeTabId: activeKept ? active.activeTabId : kept.first.tabId,
    );
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistPanel(updated);
  }

  Future<void> _onDuplicateTab(
    DuplicateTab event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.isEmpty) return;
    final active = _activePanel;
    final index = active.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1) return;
    final dup = HttpRequestTabEntity(
      tabId: _uuid.v4(),
      config: active.tabs[index].config.copyWith(),
    );
    final tabs = [...active.tabs]..insert(index + 1, dup);
    final updated = active.copyWith(tabs: tabs, activeTabId: dup.tabId);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _guardWrite(() => _repository.putTab(dup));
    await _persistPanel(updated);
  }

  Future<void> _onSendRequest(
    SendRequest event,
    Emitter<TabsState> emit,
  ) async {
    final tab = _findTab(event.tabId);
    if (tab == null || tab.isSending) return;

    final tabId = tab.tabId;
    final config = tab.config;
    final handle = _requests.start(tabId);

    // Clear the previous run's rule results when a new send starts.
    emit(
      _derive(
        _replaceTabAcrossPanels(
          tab.copyWith(
            isSending: true,
            extractionResults: const [],
            assertionResults: const [],
          ),
        ),
        state.activePanelId,
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
    final tab = _findTab(event.tabId);
    if (tab == null) return;
    final entry = tab.responseHistory.firstWhereOrNull(
      (e) => e.id == event.entryId,
    );
    if (entry == null) return;
    emit(
      _derive(
        _replaceTabAcrossPanels(tab.copyWith(response: entry.response)),
        state.activePanelId,
      ),
    );
    _markResponseDirty(event.tabId);
  }

  /// Schedule a debounced persist for the tab that just received a response
  /// (or error response) so cached responses survive a restart. No-op when the
  /// tab was closed while the request ran.
  void _markResponseDirty(String tabId) {
    if (_findTab(tabId) == null) return;
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
    final live = _findTab(tabId);
    if (live == null) return;
    emit(
      _derive(_replaceTabAcrossPanels(transform(live)), state.activePanelId),
    );
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

  void _onCancelRequest(CancelRequest event, Emitter<TabsState> emit) {
    _requests.cancel(event.tabId);
  }

  Future<void> _onAddPanel(AddPanel event, Emitter<TabsState> emit) async {
    final panelId = _uuid.v4();
    // A new panel starts empty (no seeded tab) — it shows the "NO OPEN TABS"
    // placeholder until the user adds a request.
    final panel = PanelEntity(
      id: panelId,
      name: event.name ?? _nextPanelName(),
      tabs: const [],
      activeTabId: '',
    );
    emit(_derive([...state.panels, panel], panelId));
    await _persistPanel(panel);
    await _persistPanelMeta();
  }

  Future<void> _onRemovePanel(
    RemovePanel event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.length <= 1) return;
    final idx = state.panels.indexWhere((p) => p.id == event.panelId);
    if (idx == -1) return;
    final removed = state.panels[idx];
    for (final t in removed.tabs) {
      _requests.cancelAndFinish(t.tabId);
      _dirtyTabIds.remove(t.tabId);
    }
    final newPanels = [...state.panels]..removeAt(idx);
    var activeId = state.activePanelId;
    if (activeId == event.panelId) {
      activeId = newPanels[(idx - 1).clamp(0, newPanels.length - 1)].id;
    }
    emit(_derive(newPanels, activeId));
    await _guardWrite(
      () => _repository.deleteTabs(removed.tabs.map((t) => t.tabId).toList()),
    );
    await _guardWrite(() => _repository.deletePanels([event.panelId]));
    await _persistPanelMeta();
  }

  Future<void> _onRenamePanel(
    RenamePanel event,
    Emitter<TabsState> emit,
  ) async {
    final panel = state.panels.byId(event.panelId);
    if (panel == null) return;
    final trimmed = event.name.trim();
    // When the name is blanked, reset to a "Panel N" auto-name. Exclude the
    // panel being renamed from the used-names set so it can reclaim its own
    // slot (e.g. renaming "Panel 1" to "" resets back to "Panel 1").
    final name = trimmed.isEmpty
        ? _nextPanelNameExcluding(event.panelId)
        : trimmed;
    final updated = panel.copyWith(name: name);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _persistPanel(updated);
  }

  Future<void> _onSetActivePanel(
    SetActivePanel event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.byId(event.panelId) == null) return;
    if (event.panelId == state.activePanelId) return;
    emit(_derive(state.panels, event.panelId));
    await _persistPanelMeta();
  }

  Future<void> _onReorderPanels(
    ReorderPanels event,
    Emitter<TabsState> emit,
  ) async {
    final panels = [...state.panels];
    var newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final item = panels.removeAt(event.oldIndex);
    panels.insert(newIndex, item);
    emit(_derive(panels, state.activePanelId));
    await _persistPanelMeta();
  }

  /// Removes [tabId] from its owning panel, fixing the panel's active tab.
  /// The source may empty out (it is left empty, not re-seeded). Returns
  /// (updatedSource, movedTab) or null if the tab isn't found. Persistence of
  /// the source is the caller's job.
  ({PanelEntity source, HttpRequestTabEntity tab})? _detachTab(String tabId) {
    final source = state.panels.firstWhereOrNull(
      (p) => p.tabs.any((t) => t.tabId == tabId),
    );
    if (source == null) return null;
    final removedIdx = source.tabs.indexWhere((t) => t.tabId == tabId);
    final tab = source.tabs[removedIdx];
    final remaining = [...source.tabs]..removeAt(removedIdx);
    var updated = source.copyWith(tabs: remaining);
    if (source.activeTabId == tabId) {
      updated = updated.copyWith(
        activeTabId: remaining.isEmpty
            ? ''
            : remaining[removedIdx.clamp(0, remaining.length - 1)].tabId,
      );
    }
    return (source: updated, tab: tab);
  }

  Future<void> _onMoveTabToPanel(
    MoveTabToPanel event,
    Emitter<TabsState> emit,
  ) async {
    final target = state.panels.byId(event.targetPanelId);
    if (target == null) return;
    final owner = state.panels.firstWhereOrNull(
      (p) => p.tabs.any((t) => t.tabId == event.tabId),
    );
    if (owner == null || owner.id == target.id) return;

    final detached = _detachTab(event.tabId);
    if (detached == null) return;
    final updatedTarget = target.copyWith(
      tabs: [...target.tabs, detached.tab],
    );

    var panels = _replacePanel(state.panels, detached.source);
    panels = _replacePanel(panels, updatedTarget);
    emit(_derive(panels, state.activePanelId)); // stay on current panel
    await _persistPanel(detached.source);
    await _persistPanel(updatedTarget);
  }

  Future<void> _onMoveTabToNewPanel(
    MoveTabToNewPanel event,
    Emitter<TabsState> emit,
  ) async {
    final detached = _detachTab(event.tabId);
    if (detached == null) return;
    final newPanel = PanelEntity(
      id: _uuid.v4(),
      name: event.name ?? _nextPanelName(),
      tabs: [detached.tab],
      activeTabId: detached.tab.tabId,
    );
    final panels = [..._replacePanel(state.panels, detached.source), newPanel];
    emit(_derive(panels, state.activePanelId)); // stay on current panel
    await _persistPanel(detached.source);
    await _persistPanel(newPanel);
    await _persistPanelMeta();
  }
}

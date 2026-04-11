import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/request_tab_entity.dart';
import '../../domain/repositories/tabs_repository.dart';
import '../../../history/domain/entities/request_config_entity.dart';
import '../../../history/domain/usecases/history_usecases.dart';
import '../../../settings/domain/usecases/settings_usecases.dart';
import '../../../../core/network/network_service.dart';
import '../../../history/presentation/bloc/history_bloc.dart';
import '../../../history/presentation/bloc/history_event.dart';
import 'tabs_event.dart';
import 'tabs_state.dart';

String _jsonEncode(dynamic data) => json.encode(data);

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository repository;
  final NetworkService networkService;
  final AddToHistoryUseCase addToHistoryUseCase;
  final GetSettingsUseCase getSettingsUseCase;
  final HistoryBloc historyBloc;
  
  final Map<String, CancelToken> _cancelTokens = {};
  Timer? _debounceTimer;
  final Uuid uuid = const Uuid();

  TabsBloc({
    required this.repository,
    required this.networkService,
    required this.addToHistoryUseCase,
    required this.getSettingsUseCase,
    required this.historyBloc,
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
    _debounceTimer = Timer(const Duration(seconds: 10), () {
      repository.saveTabs(state.tabs);
    });
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    repository.saveTabs(state.tabs);
    return super.close();
  }

  Future<void> _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) async {
    emit(state.copyWith(isLoading: true));
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
    if (state.tabs.length <= 1) return;

    final newTabs = [...state.tabs]..removeAt(event.index);
    int newActiveIndex = state.activeIndex;
    if (newActiveIndex >= newTabs.length) {
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
    final activeTab = state.tabs[state.activeIndex];
    final config = activeTab.config;

    final cancelToken = CancelToken();
    _cancelTokens[activeTab.tabId] = cancelToken;

    final sendingTab = activeTab.copyWith(isSending: true);
    final tabsWithSending = [...state.tabs];
    tabsWithSending[state.activeIndex] = sendingTab;
    emit(state.copyWith(tabs: tabsWithSending));

    final stopwatch = Stopwatch()..start();
    try {
      final response = await networkService.request(
        url: config.url,
        method: config.method,
        data: config.body.isNotEmpty ? config.body : null,
        queryParameters: config.params,
        headers: config.headers,
        cancelToken: cancelToken,
      );

      stopwatch.stop();
      final duration = stopwatch.elapsedMilliseconds;

      String responseBody;
      if (response.data is String) {
        responseBody = response.data;
      } else {
        try {
          responseBody = await compute(_jsonEncode, response.data);
        } catch (_) {
          responseBody = response.data.toString();
        }
      }

      final updatedTab = sendingTab.copyWith(
        isSending: false,
        statusCode: response.statusCode,
        durationMs: duration,
        responseBody: responseBody,
        responseHeaders: response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      );

      _cancelTokens.remove(activeTab.tabId);
      final finalTabs = [...state.tabs];
      finalTabs[state.activeIndex] = updatedTab;
      emit(state.copyWith(tabs: finalTabs));

      // Save to History
      final settings = await getSettingsUseCase();
      HttpRequestConfigEntity historyConfig = config.copyWith(); 
      
      if (settings.saveResponseInHistory) {
        historyConfig = historyConfig.copyWith(
          responseBody: updatedTab.responseBody,
          responseHeaders: updatedTab.responseHeaders,
          statusCode: updatedTab.statusCode,
          durationMs: updatedTab.durationMs,
        );
      }
      
      await addToHistoryUseCase(historyConfig, settings.historyLimit);
      historyBloc.add(LoadHistory());
    } catch (e) {
      _cancelTokens.remove(activeTab.tabId);
      
      if (e is DioException && e.type == DioExceptionType.cancel) {
        final cancelledTabs = [...state.tabs];
        cancelledTabs[state.activeIndex] = activeTab.copyWith(isSending: false);
        emit(state.copyWith(tabs: cancelledTabs));
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
               errorBody = await compute(_jsonEncode, e.response!.data);
             } catch (_) {
               errorBody = e.response!.data.toString();
             }
           }        } else {
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
      
      final errorTabs = [...state.tabs];
      errorTabs[state.activeIndex] = updatedTab;
      emit(state.copyWith(tabs: errorTabs));

      // Save failed request to history too
      final settings = await getSettingsUseCase();
      HttpRequestConfigEntity historyConfig = config.copyWith();
      if (settings.saveResponseInHistory) {
        historyConfig = historyConfig.copyWith(
          responseBody: updatedTab.responseBody,
          responseHeaders: updatedTab.responseHeaders,
          statusCode: updatedTab.statusCode,
          durationMs: updatedTab.durationMs,
        );
      }
      await addToHistoryUseCase(historyConfig, settings.historyLimit);
      historyBloc.add(LoadHistory());
    }
  }

  void _onCancelRequest(CancelRequest event, Emitter<TabsState> emit) {
    final tab = state.tabs[event.index];
    final token = _cancelTokens[tab.tabId];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled request');
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart';
import 'package:getman/features/tabs/presentation/widgets/response_area.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart';
import 'package:getman/features/tabs/presentation/widgets/url_bar.dart';
import 'package:re_editor/re_editor.dart';
import 'package:uuid/uuid.dart';

const double _splitMin = 0.1;
const double _splitMax = 0.9;
const int _splitFlexUnits = 1000;

int _ratioToFlex(double ratio) =>
    (ratio.clamp(_splitMin, _splitMax) * _splitFlexUnits).toInt();

class RequestView extends StatefulWidget {
  const RequestView({required this.tabId, super.key});
  final String tabId;

  @override
  State<RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends State<RequestView> {
  late final CodeLineEditingController _bodyController;
  late final CodeLineEditingController _graphqlVarsController;
  late final CodeLineEditingController _responseController;
  // Live drag ratio. A ValueNotifier (not setState) so dragging the splitter
  // only re-runs the Flex layout — the captured request/response panes (and
  // their code editors) are not rebuilt frame-by-frame. Committed to the
  // SettingsBloc on drag end, then reset to null so the bloc value drives
  // again.
  final ValueNotifier<double?> _localSplitRatio = ValueNotifier<double?>(null);

  @override
  void initState() {
    super.initState();
    _bodyController = createJsonCodeController();
    _graphqlVarsController = createJsonCodeController();
    _responseController = createJsonCodeController();
    _bodyController.addListener(_onBodyChanged);
    _graphqlVarsController.addListener(_onGraphqlVarsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    if (tab != null && _bodyController.text != tab.config.body) {
      _bodyController.text = tab.config.body;
    }
    if (tab != null &&
        _graphqlVarsController.text != tab.config.graphqlVariables) {
      _graphqlVarsController.text = tab.config.graphqlVariables;
    }
  }

  void _onGraphqlVarsChanged() {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.byId(widget.tabId);
    if (tab == null) return;
    final newText = _graphqlVarsController.text;
    if (tab.config.graphqlVariables == newText) return;

    tabsBloc.add(
      UpdateTab(
        tab.copyWith(config: tab.config.copyWith(graphqlVariables: newText)),
      ),
    );
  }

  void _onBodyChanged() {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.byId(widget.tabId);
    if (tab == null) return;
    final newText = _bodyController.text;
    if (tab.config.body == newText) return;

    tabsBloc.add(
      UpdateTab(
        tab.copyWith(config: tab.config.copyWith(body: newText)),
      ),
    );
  }

  @override
  void dispose() {
    _bodyController
      ..removeListener(_onBodyChanged)
      ..dispose();
    _graphqlVarsController
      ..removeListener(_onGraphqlVarsChanged)
      ..dispose();
    _responseController.dispose();
    _localSplitRatio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (prev, next) =>
          prev.settings.splitRatio != next.settings.splitRatio ||
          prev.settings.isVerticalLayout != next.settings.isVerticalLayout,
      builder: (context, settingsState) {
        final settings = settingsState.settings;
        final layout = context.appLayout;

        return BlocConsumer<TabsBloc, TabsState>(
          listenWhen: (prev, next) {
            final p = prev.tabs.byId(widget.tabId);
            final n = next.tabs.byId(widget.tabId);
            return p?.config.body != n?.config.body ||
                p?.config.graphqlVariables != n?.config.graphqlVariables;
          },
          listener: (context, state) {
            final tab = state.tabs.byId(widget.tabId);
            if (tab == null) return;
            if (_bodyController.text != tab.config.body) {
              _bodyController.text = tab.config.body;
            }
            if (_graphqlVarsController.text != tab.config.graphqlVariables) {
              _graphqlVarsController.text = tab.config.graphqlVariables;
            }
          },
          buildWhen: (prev, next) {
            if (prev.isLoading != next.isLoading) return true;
            final prevExists = prev.tabs.any((t) => t.tabId == widget.tabId);
            final nextExists = next.tabs.any((t) => t.tabId == widget.tabId);
            return prevExists != nextExists;
          },
          builder: (context, tabsState) {
            if (tabsState.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final tab = tabsState.tabs.byId(widget.tabId);
            if (tab == null) return const SizedBox.shrink();

            return Actions(
              actions: <Type, Action<Intent>>{
                SaveRequestIntent: CallbackAction<SaveRequestIntent>(
                  onInvoke: (_) => _handleSave(context),
                ),
                BeautifyJsonIntent: CallbackAction<BeautifyJsonIntent>(
                  onInvoke: (_) async {
                    final prettified = await JsonUtils.prettify(
                      _bodyController.text,
                    );
                    _bodyController.text = prettified;
                    return null;
                  },
                ),
              },
              child: Focus(
                autofocus: true,
                child: Padding(
                  // On the desktop split-pane layout, align the content's left
                  // edge with the open-request tab strip above it (which sits
                  // flush against the side-menu divider) by dropping the left
                  // page padding. The drawer layout (tablet/phone) keeps full
                  // padding so content isn't flush against the screen edge.
                  padding: EdgeInsets.fromLTRB(
                    context.useDrawerNav ? layout.pagePadding : 0,
                    layout.pagePadding,
                    layout.pagePadding,
                    layout.pagePadding,
                  ),
                  child: Column(
                    children: [
                      UrlBar(
                        tabId: widget.tabId,
                        onSave: () => _handleSave(context),
                      ),
                      SizedBox(height: layout.sectionSpacing),
                      Expanded(
                        child: context.useUnifiedRequestTabs
                            ? UnifiedRequestPanel(
                                tabId: widget.tabId,
                                bodyController: _bodyController,
                                variablesController: _graphqlVarsController,
                                responseController: _responseController,
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final totalSize = settings.isVerticalLayout
                                      ? constraints.maxHeight
                                      : constraints.maxWidth;
                                  // Build the panes once; only the Flex (below)
                                  // rebuilds on drag, so the editors relayout
                                  // rather than rebuild.
                                  final requestPane = RequestConfigSection(
                                    tabId: widget.tabId,
                                    bodyController: _bodyController,
                                    variablesController: _graphqlVarsController,
                                  );
                                  final responsePane = ResponseArea(
                                    tabId: widget.tabId,
                                    responseController: _responseController,
                                  );
                                  final splitter = Splitter(
                                    isVertical: settings.isVerticalLayout,
                                    onUpdate: (delta) {
                                      final base =
                                          _localSplitRatio.value ??
                                          settings.splitRatio;
                                      _localSplitRatio.value =
                                          (base + delta / totalSize).clamp(
                                            _splitMin,
                                            _splitMax,
                                          );
                                    },
                                    onEnd: () {
                                      final committed = _localSplitRatio.value;
                                      if (committed == null) return;
                                      context.read<SettingsBloc>().add(
                                        UpdateSplitRatio(committed),
                                      );
                                      _localSplitRatio.value = null;
                                    },
                                  );

                                  return ValueListenableBuilder<double?>(
                                    valueListenable: _localSplitRatio,
                                    builder: (context, local, _) {
                                      final currentRatio =
                                          local ?? settings.splitRatio;
                                      return Flex(
                                        direction: settings.isVerticalLayout
                                            ? Axis.vertical
                                            : Axis.horizontal,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Flexible(
                                            flex: _ratioToFlex(currentRatio),
                                            child: requestPane,
                                          ),
                                          splitter,
                                          Flexible(
                                            flex: _ratioToFlex(
                                              1 - currentRatio,
                                            ),
                                            child: responsePane,
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleSave(BuildContext context) {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.byId(widget.tabId);
    if (tab == null) return;

    final collectionsBloc = context.read<CollectionsBloc>();

    final savedNode = tab.collectionNodeId == null
        ? null
        : CollectionsTreeHelper.findNode(
            collectionsBloc.state.collections,
            tab.collectionNodeId!,
          );

    if (savedNode != null) {
      collectionsBloc.add(
        UpdateNodeRequest(
          tab.collectionNodeId!,
          tab.config.copyWith(),
        ),
      );
      showAppSnackBar(
        context,
        'REQUEST UPDATED!',
        duration: const Duration(seconds: 1),
      );
      return;
    }

    if (tab.collectionNodeId != null) {
      // Node was deleted while the tab was open — drop the stale link
      // (copyWith's sentinel pattern lets `null` actually clear the fields).
      tabsBloc.add(
        UpdateTab(
          tab.copyWith(collectionNodeId: null, collectionName: null),
        ),
      );
    }
    _showSaveDialog(context, tab);
  }

  void _showSaveDialog(BuildContext context, HttpRequestTabEntity tab) {
    final collectionsBloc = context.read<CollectionsBloc>();
    final tabsBloc = context.read<TabsBloc>();
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'SAVE TO COLLECTION',
        initialText: 'NEW REQUEST',
        hintText: 'REQUEST NAME',
        onConfirm: (name) {
          // Generate the node id at the call site so the open tab can link to
          // the new node immediately (otherwise it stays unlinked: shows dirty,
          // the Save button never flips to "Update", and re-saving duplicates).
          final nodeId = const Uuid().v4();
          collectionsBloc.add(
            SaveRequestToCollection(name, tab.config.copyWith(), id: nodeId),
          );
          tabsBloc.add(
            UpdateTab(
              tab.copyWith(collectionName: name, collectionNodeId: nodeId),
            ),
          );
        },
      ),
    );
  }
}

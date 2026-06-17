import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/curl_utils.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/core/utils/request_variable_resolver.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/code_export_dialog.dart';
import 'package:getman/features/tabs/presentation/widgets/realtime_button.dart';
import 'package:getman/features/tabs/presentation/widgets/request_kind_method_selector.dart';
import 'package:getman/features/tabs/presentation/widgets/url_overflow_menu.dart';

void _setControllerPreservingEnd(
  TextEditingController controller,
  String text,
) {
  if (controller.text == text) return;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

class UrlBar extends StatefulWidget {
  const UrlBar({required this.tabId, required this.onSave, super.key});
  final String tabId;
  final VoidCallback onSave;

  @override
  State<UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<UrlBar> {
  late final VariableHighlightController _urlController;
  final VariableHoverController _hoverController = VariableHoverController();
  late final FocusNode _urlFocusNode;
  UrlFocusRegistry? _focusRegistry;

  @override
  void initState() {
    super.initState();
    // Token colors come from AppPalette in didChangeDependencies — never
    // hardcode them here (CLAUDE.md §4.10).
    _urlController = VariableHighlightController()
      ..onVariableEnter = _showVariablePopover
      ..onVariableExit = _hoverController.scheduleHide;
    // Register this tab's URL field so the Cmd/Ctrl+L shortcut can focus it.
    _urlFocusNode = FocusNode(debugLabel: 'url_${widget.tabId}');
    _focusRegistry = context.read<UrlFocusRegistry>()
      ..register(widget.tabId, _urlFocusNode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    if (tab != null) {
      _setControllerPreservingEnd(_urlController, tab.config.url);
    }
    _syncHighlight(context);
  }

  void _syncHighlight(BuildContext context) {
    final palette = context.appPalette;
    _urlController
      ..updateColors(
        resolved: palette.variableResolved,
        unresolved: palette.variableUnresolved,
      )
      ..updateVariables(_activeVariables(context));
  }

  Map<String, String> _activeVariables(BuildContext context) {
    final envState = context.read<EnvironmentsBloc>().state;
    final settings = context.read<SettingsBloc>().state.settings;
    final collections = context.read<CollectionsBloc>().state.collections;
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    return RequestVariableResolver.variablesFor(
      environments: envState.environments,
      activeEnvironmentId: settings.activeEnvironmentId,
      collections: collections,
      collectionNodeId: tab?.collectionNodeId,
    );
  }

  // Resolves the full active environment (not just its variables, as
  // _activeVariables does) because the popover needs the name + secretKeys to
  // mask secrets and label the source. Both read live bloc state at call time.
  void _showVariablePopover(String name, Offset globalPosition) {
    if (!mounted) return;
    final envState = context.read<EnvironmentsBloc>().state;
    final settings = context.read<SettingsBloc>().state.settings;
    final env = ActiveEnvironmentHelper.activeEnvironment(
      envState.environments,
      settings.activeEnvironmentId,
    );
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    final collected = tab?.collectionNodeId == null
        ? (variables: const <String, String>{}, secretKeys: const <String>{})
        : CollectionsTreeHelper.collectVariables(
            context.read<CollectionsBloc>().state.collections,
            tab!.collectionNodeId!,
          );
    final data = VariableResolutionHelper.classifyLayered(
      name: name,
      collectionVariables: collected.variables,
      collectionSecrets: collected.secretKeys,
      environmentVariables: env?.variables ?? const {},
      environmentSecrets: env?.secretKeys ?? const {},
      environmentName: env?.name,
    );
    _hoverController.showFor(context, data, globalPosition);
  }

  @override
  void dispose() {
    _focusRegistry?.unregister(widget.tabId, _urlFocusNode);
    _urlFocusNode.dispose();
    _hoverController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<EnvironmentsBloc, EnvironmentsState>(
          listenWhen: (p, n) => p.environments != n.environments,
          listener: (ctx, _) => _syncHighlight(ctx),
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (p, n) =>
              p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
          listener: (ctx, _) => _syncHighlight(ctx),
        ),
        BlocListener<CollectionsBloc, CollectionsState>(
          listenWhen: (p, n) => p.collections != n.collections,
          listener: (ctx, _) => _syncHighlight(ctx),
        ),
      ],
      child: BlocConsumer<TabsBloc, TabsState>(
        listenWhen: (prev, next) {
          final p = prev.tabs.byId(widget.tabId);
          final n = next.tabs.byId(widget.tabId);
          return p?.config.url != n?.config.url;
        },
        listener: (context, state) {
          final tab = state.tabs.byId(widget.tabId);
          if (tab == null) return;
          _setControllerPreservingEnd(_urlController, tab.config.url);
        },
        buildWhen: (prev, next) {
          final p = prev.tabs.byId(widget.tabId);
          final n = next.tabs.byId(widget.tabId);
          if (p == null || n == null) return true;
          return p.config.method != n.config.method ||
              p.config.kind != n.config.kind ||
              p.isSending != n.isSending ||
              p.collectionNodeId != n.collectionNodeId;
        },
        builder: (context, state) {
          final tab = state.tabs.byId(widget.tabId);
          if (tab == null) return const SizedBox.shrink();

          return BlocBuilder<SettingsBloc, SettingsState>(
            buildWhen: (prev, next) =>
                prev.settings.isVerticalLayout !=
                next.settings.isVerticalLayout,
            builder: (context, settingsState) {
              final settings = settingsState.settings;
              final layout = context.appLayout;
              final theme = Theme.of(context);

              return context.appDecoration.frost(
                context,
                borderRadius: BorderRadius.circular(
                  context.appShape.panelRadius,
                ),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: context.appDecoration.panelBox(
                    context,
                    offset: layout.cardOffset,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Below this threshold, collapse cURL / Save /
                      // Layout-toggle into a single overflow menu so
                      // Method + URL + SEND always fit.
                      final isNarrow = constraints.maxWidth < 560;
                      final iconSize = isNarrow
                          ? 22.0
                          : (layout.isCompact ? 24.0 : 28.0);
                      final gap = isNarrow
                          ? 4.0
                          : (layout.isCompact ? 8.0 : 12.0);
                      final smallGap = isNarrow
                          ? 2.0
                          : (layout.isCompact ? 4.0 : 8.0);

                      return Row(
                        children: [
                          RequestKindMethodSelector(
                            tab: tab,
                            isNarrow: isNarrow,
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('url_field'),
                              controller: _urlController,
                              focusNode: _urlFocusNode,
                              style: TextStyle(
                                fontSize: layout.fontSizeTitle,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Enter URL or paste cURL...',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                filled: false,
                              ),
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              enableSuggestions: false,
                              onChanged: (val) =>
                                  _handleUrlChanged(context, tab, val),
                            ),
                          ),
                          SizedBox(width: gap),
                          if (!isNarrow) ...[
                            context.appDecoration.wrapInteractive(
                              child: IconButton(
                                key: const ValueKey('code_export_button'),
                                icon: Icon(
                                  Icons.code,
                                  color: theme.colorScheme.secondary,
                                  size: iconSize,
                                ),
                                tooltip: 'Generate code',
                                // Read the CURRENT config at press time: this
                                // BlocBuilder's buildWhen excludes config.url
                                // (the editor must not rebuild per keystroke),
                                // so `tab` here goes stale after a URL edit.
                                // Mirrors the RealtimeButton fix.
                                onPressed: () => CodeExportDialog.show(
                                  context,
                                  context
                                          .read<TabsBloc>()
                                          .state
                                          .tabs
                                          .byId(widget.tabId)
                                          ?.config ??
                                      tab.config,
                                ),
                              ),
                            ),
                            SizedBox(width: smallGap),
                          ],
                          if (tab.config.kind == RequestKind.http)
                            context.appDecoration.wrapInteractive(
                              child: ElevatedButton(
                                onPressed: tab.isSending
                                    ? () => context.read<TabsBloc>().add(
                                        CancelRequest(tab.tabId),
                                      )
                                    : () => context.read<TabsBloc>().add(
                                        SendRequest(
                                          tabId: tab.tabId,
                                          envVars: _activeVariables(context),
                                        ),
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: tab.isSending
                                      ? theme.colorScheme.error
                                      : null,
                                  foregroundColor: tab.isSending
                                      ? theme.colorScheme.onError
                                      : null,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow
                                        ? 12
                                        : layout.buttonPaddingHorizontal,
                                    vertical: isNarrow
                                        ? 10
                                        : layout.buttonPaddingVertical,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, animation) =>
                                      ScaleTransition(
                                        scale: animation,
                                        child: FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                      ),
                                  child: tab.isSending
                                      ? Row(
                                          key: const ValueKey('cancel'),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: layout.smallIconSize,
                                              height: layout.smallIconSize,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color:
                                                    theme.colorScheme.onError,
                                              ),
                                            ),
                                            SizedBox(width: isNarrow ? 4 : 8),
                                            Text(
                                              isNarrow ? 'STOP' : 'CANCEL',
                                              style: TextStyle(
                                                fontSize: layout.fontSizeTitle,
                                                fontWeight: context
                                                    .appTypography
                                                    .displayWeight,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          'SEND',
                                          key: const ValueKey('send'),
                                          style: TextStyle(
                                            fontSize: layout.fontSizeTitle,
                                            fontWeight: context
                                                .appTypography
                                                .displayWeight,
                                          ),
                                        ),
                                ),
                              ),
                            )
                          else
                            RealtimeButton(
                              tabId: tab.tabId,
                              config: tab.config,
                              isNarrow: isNarrow,
                              activeVars: _activeVariables(context),
                            ),
                          if (isNarrow) ...[
                            SizedBox(width: smallGap),
                            UrlOverflowMenu(
                              iconSize: iconSize,
                              isSaved: tab.collectionNodeId != null,
                              isVerticalLayout: settings.isVerticalLayout,
                              onGenerateCode: () => CodeExportDialog.show(
                                context,
                                context
                                        .read<TabsBloc>()
                                        .state
                                        .tabs
                                        .byId(widget.tabId)
                                        ?.config ??
                                    tab.config,
                              ),
                              onSave: widget.onSave,
                              onToggleLayout: () =>
                                  context.read<SettingsBloc>().add(
                                    UpdateVerticalLayout(
                                      isVerticalLayout:
                                          !settings.isVerticalLayout,
                                    ),
                                  ),
                            ),
                          ] else ...[
                            SizedBox(width: gap),
                            context.appDecoration.wrapInteractive(
                              child: IconButton(
                                key: const ValueKey('save_request_button'),
                                icon: Icon(
                                  tab.collectionNodeId != null
                                      ? Icons.save
                                      : Icons.save_as,
                                  color: theme.colorScheme.secondary,
                                  size: iconSize,
                                ),
                                tooltip: tab.collectionNodeId != null
                                    ? 'Update Request'
                                    : 'Save to Collection',
                                onPressed: widget.onSave,
                              ),
                            ),
                            SizedBox(width: smallGap),
                            context.appDecoration.wrapInteractive(
                              child: IconButton(
                                icon: Icon(
                                  settings.isVerticalLayout
                                      ? Icons.view_column_rounded
                                      : Icons.view_agenda_rounded,
                                  color: theme.colorScheme.onSurface,
                                  size: iconSize,
                                ),
                                tooltip: settings.isVerticalLayout
                                    ? 'Horizontal Layout'
                                    : 'Vertical Layout',
                                onPressed: () =>
                                    context.read<SettingsBloc>().add(
                                      UpdateVerticalLayout(
                                        isVerticalLayout:
                                            !settings.isVerticalLayout,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _handleUrlChanged(
    BuildContext context,
    HttpRequestTabEntity tab,
    String val,
  ) {
    if (tab.config.url == val) return;
    final tabsBloc = context.read<TabsBloc>();

    if (val.trim().toLowerCase().startsWith('curl ')) {
      final parsedConfig = CurlUtils.parse(val, id: tab.config.id);
      if (parsedConfig != null) {
        tabsBloc.add(UpdateTab(tab.copyWith(config: parsedConfig)));
        unawaited(
          _prettifyAndUpdateBody(tabsBloc, tab.tabId, parsedConfig.body),
        );
        return;
      }
    }

    tabsBloc.add(
      UpdateTab(tab.copyWith(config: tab.config.copyWith(url: val))),
    );
  }

  Future<void> _prettifyAndUpdateBody(
    TabsBloc tabsBloc,
    String tabId,
    String rawBody,
  ) async {
    final prettified = await JsonUtils.prettify(rawBody);
    final latestTab = tabsBloc.state.tabs.byId(tabId);
    if (latestTab == null) return;
    // If the user edited the body while prettify ran in its isolate, don't
    // clobber that newer edit with the stale prettified result.
    if (latestTab.config.body != rawBody) return;
    if (latestTab.config.body == prettified) return;
    tabsBloc.add(
      UpdateTab(
        latestTab.copyWith(config: latestTab.config.copyWith(body: prettified)),
      ),
    );
  }
}

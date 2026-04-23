import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/http_methods.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/utils/curl_utils.dart';
import 'package:getman/core/utils/json_utils.dart';
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

void _setControllerPreservingEnd(TextEditingController controller, String text) {
  if (controller.text == text) return;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

class UrlBar extends StatefulWidget {
  final String tabId;
  final VoidCallback onSave;
  const UrlBar({super.key, required this.tabId, required this.onSave});

  @override
  State<UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<UrlBar> {
  late final VariableHighlightController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = VariableHighlightController(
      resolvedColor: const Color(0xFF16A34A),
      unresolvedColor: const Color(0xFFDC2626),
    );
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
    _urlController.updateColors(
      resolved: palette.variableResolved,
      unresolved: palette.variableUnresolved,
    );
    _urlController.updateVariables(_activeVariables(context));
  }

  Map<String, String> _activeVariables(BuildContext context) {
    final envState = context.read<EnvironmentsBloc>().state;
    final settings = context.read<SettingsBloc>().state.settings;
    return ActiveEnvironmentHelper.variablesFor(
      envState.environments,
      settings.activeEnvironmentId,
    );
  }

  @override
  void dispose() {
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
          listenWhen: (p, n) => p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
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
              p.isSending != n.isSending ||
              p.collectionNodeId != n.collectionNodeId;
        },
        builder: (context, state) {
          final tab = state.tabs.byId(widget.tabId);
          if (tab == null) return const SizedBox.shrink();

          return BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              final settings = settingsState.settings;
              final layout = context.appLayout;
              final theme = Theme.of(context);

              return Container(
                padding: const EdgeInsets.all(6),
                decoration: context.appDecoration.panelBox(context, offset: layout.cardOffset),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Below this threshold, collapse cURL / Save / Layout-toggle
                    // into a single overflow menu so Method + URL + SEND always fit.
                    final isNarrow = constraints.maxWidth < 560;
                    final iconSize = isNarrow ? 22.0 : (layout.isCompact ? 24.0 : 28.0);
                    final gap = isNarrow ? 4.0 : (layout.isCompact ? 8.0 : 12.0);
                    final smallGap = isNarrow ? 2.0 : (layout.isCompact ? 4.0 : 8.0);

                    return Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 6 : (layout.isCompact ? 8 : 12)),
                          decoration: BoxDecoration(
                            border: Border(right: BorderSide(color: theme.dividerColor, width: layout.borderThick)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              dropdownColor: theme.colorScheme.surface,
                              value: tab.config.method,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: context.appTypography.displayWeight,
                                fontSize: layout.fontSizeNormal,
                              ),
                              selectedItemBuilder: (context) {
                                return HttpMethods.all.map((m) => Center(child: MethodBadge(method: m))).toList();
                              },
                              items: HttpMethods.all
                                  .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: SizedBox(
                                      width: isNarrow ? 64 : (layout.isCompact ? 80 : 100),
                                      child: Center(child: MethodBadge(method: m)),
                                    ),
                                  ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null && tab.config.method != val) {
                                  context.read<TabsBloc>().add(UpdateTab(
                                    tab.copyWith(config: tab.config.copyWith(method: val)),
                                  ));
                                }
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
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
                            textCapitalization: TextCapitalization.none,
                            onChanged: (val) => _handleUrlChanged(context, tab, val),
                          ),
                        ),
                        SizedBox(width: gap),
                        if (!isNarrow) ...[
                          context.appDecoration.wrapInteractive(
                            child: IconButton(
                              icon: Icon(Icons.code, color: theme.colorScheme.secondary, size: iconSize),
                              tooltip: 'Copy as cURL',
                              onPressed: () => _copyAsCurl(context, tab),
                            ),
                          ),
                          SizedBox(width: smallGap),
                        ],
                        context.appDecoration.wrapInteractive(
                          child: ElevatedButton(
                            onPressed: tab.isSending
                              ? () => context.read<TabsBloc>().add(CancelRequest(tab.tabId))
                              : () => context.read<TabsBloc>().add(SendRequest(envVars: _activeVariables(context))),
                            style: ElevatedButton.styleFrom(
                               backgroundColor: tab.isSending ? theme.colorScheme.error : null,
                               foregroundColor: tab.isSending ? theme.colorScheme.onError : null,
                               padding: EdgeInsets.symmetric(
                                 horizontal: isNarrow ? 12 : layout.buttonPaddingHorizontal,
                                 vertical: isNarrow ? 10 : layout.buttonPaddingVertical,
                               ),
                               minimumSize: Size.zero,
                               tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
                              child: tab.isSending
                                ? Row(
                                    key: const ValueKey('cancel'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: layout.smallIconSize,
                                        height: layout.smallIconSize,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onError),
                                      ),
                                      SizedBox(width: isNarrow ? 4 : 8),
                                      Text(isNarrow ? 'STOP' : 'CANCEL', style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: context.appTypography.displayWeight)),
                                    ],
                                  )
                                : Text('SEND', key: const ValueKey('send'), style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: context.appTypography.displayWeight)),
                            ),
                          ),
                        ),
                        if (isNarrow) ...[
                          SizedBox(width: smallGap),
                          _OverflowMenu(
                            iconSize: iconSize,
                            isSaved: tab.collectionNodeId != null,
                            isVerticalLayout: settings.isVerticalLayout,
                            onCopyCurl: () => _copyAsCurl(context, tab),
                            onSave: widget.onSave,
                            onToggleLayout: () => context.read<SettingsBloc>().add(UpdateVerticalLayout(!settings.isVerticalLayout)),
                          ),
                        ] else ...[
                          SizedBox(width: gap),
                          context.appDecoration.wrapInteractive(
                            child: IconButton(
                              icon: Icon(tab.collectionNodeId != null ? Icons.save : Icons.save_as, color: theme.colorScheme.secondary, size: iconSize),
                              tooltip: tab.collectionNodeId != null ? 'Update Request' : 'Save to Collection',
                              onPressed: widget.onSave,
                            ),
                          ),
                          SizedBox(width: smallGap),
                          context.appDecoration.wrapInteractive(
                            child: IconButton(
                              icon: Icon(
                                settings.isVerticalLayout ? Icons.view_column_rounded : Icons.view_agenda_rounded,
                                color: theme.colorScheme.onSurface,
                                size: iconSize,
                              ),
                              tooltip: settings.isVerticalLayout ? 'Horizontal Layout' : 'Vertical Layout',
                              onPressed: () => context.read<SettingsBloc>().add(UpdateVerticalLayout(!settings.isVerticalLayout)),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _copyAsCurl(BuildContext context, HttpRequestTabEntity tab) {
    final theme = Theme.of(context);
    final curl = CurlUtils.generate(tab.config);
    Clipboard.setData(ClipboardData(text: curl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('cURL command copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: theme.colorScheme.secondary,
      ),
    );
  }

  void _handleUrlChanged(BuildContext context, HttpRequestTabEntity tab, String val) {
    if (tab.config.url == val) return;
    final tabsBloc = context.read<TabsBloc>();

    if (val.trim().toLowerCase().startsWith('curl ')) {
      final parsedConfig = CurlUtils.parse(val, id: tab.config.id);
      if (parsedConfig != null) {
        tabsBloc.add(UpdateTab(tab.copyWith(config: parsedConfig)));
        _prettifyAndUpdateBody(tabsBloc, tab.tabId, parsedConfig.body);
        return;
      }
    }

    tabsBloc.add(UpdateTab(tab.copyWith(config: tab.config.copyWith(url: val))));
  }

  Future<void> _prettifyAndUpdateBody(TabsBloc tabsBloc, String tabId, String rawBody) async {
    final prettified = await JsonUtils.prettify(rawBody);
    final latestTab = tabsBloc.state.tabs.byId(tabId);
    if (latestTab == null) return;
    if (latestTab.config.body == prettified) return;
    tabsBloc.add(UpdateTab(
      latestTab.copyWith(config: latestTab.config.copyWith(body: prettified)),
    ));
  }
}

enum _OverflowAction { copyCurl, save, toggleLayout }

class _OverflowMenu extends StatelessWidget {
  final double iconSize;
  final bool isSaved;
  final bool isVerticalLayout;
  final VoidCallback onCopyCurl;
  final VoidCallback onSave;
  final VoidCallback onToggleLayout;

  const _OverflowMenu({
    required this.iconSize,
    required this.isSaved,
    required this.isVerticalLayout,
    required this.onCopyCurl,
    required this.onSave,
    required this.onToggleLayout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return PopupMenuButton<_OverflowAction>(
      tooltip: 'More actions',
      position: PopupMenuPosition.under,
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
      ),
      elevation: 0,
      icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface, size: iconSize),
      onSelected: (action) {
        switch (action) {
          case _OverflowAction.copyCurl:
            onCopyCurl();
            break;
          case _OverflowAction.save:
            onSave();
            break;
          case _OverflowAction.toggleLayout:
            onToggleLayout();
            break;
        }
      },
      itemBuilder: (popupContext) => [
        PopupMenuItem(
          value: _OverflowAction.save,
          child: _menuRow(
            context,
            isSaved ? Icons.save : Icons.save_as,
            isSaved ? 'UPDATE REQUEST' : 'SAVE TO COLLECTION',
            theme.colorScheme.secondary,
          ),
        ),
        PopupMenuItem(
          value: _OverflowAction.copyCurl,
          child: _menuRow(context, Icons.code, 'COPY AS cURL', theme.colorScheme.secondary),
        ),
        PopupMenuItem(
          value: _OverflowAction.toggleLayout,
          child: _menuRow(
            context,
            isVerticalLayout ? Icons.view_column_rounded : Icons.view_agenda_rounded,
            isVerticalLayout ? 'HORIZONTAL LAYOUT' : 'VERTICAL LAYOUT',
            theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _menuRow(BuildContext context, IconData icon, String label, Color iconColor) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: layout.smallIconSize, color: iconColor),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontWeight: context.appTypography.displayWeight,
            fontSize: layout.fontSizeNormal,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

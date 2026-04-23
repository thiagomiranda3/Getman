import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';

/// Narrow-width alternative to [RequestConfigSection] + [ResponseSection].
///
/// Collapses the split-pane editor into a single four-tab strip
/// (PARAMS / HEADERS / BODY / RESPONSE). Status metadata sits above the tab
/// strip so it stays visible on every tab. Auto-focuses the RESPONSE tab when
/// a send completes.
class UnifiedRequestPanel extends StatefulWidget {
  final String tabId;
  final CodeLineEditingController bodyController;
  final CodeLineEditingController responseController;

  const UnifiedRequestPanel({
    super.key,
    required this.tabId,
    required this.bodyController,
    required this.responseController,
  });

  @override
  State<UnifiedRequestPanel> createState() => _UnifiedRequestPanelState();
}

class _UnifiedRequestPanelState extends State<UnifiedRequestPanel> with SingleTickerProviderStateMixin {
  static const int _responseTabIndex = 3;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final p = prev.tabs.byId(widget.tabId);
        final n = next.tabs.byId(widget.tabId);
        // Send completed: isSending flipped true → false AND we have a status.
        return p?.isSending == true && n?.isSending == false && n?.statusCode != null;
      },
      listener: (context, state) {
        if (_tabController.index != _responseTabIndex) {
          _tabController.animateTo(_responseTabIndex);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusRibbon(tabId: widget.tabId),
          _UnifiedTabBar(controller: _tabController, theme: theme, layout: layout),
          Expanded(
            child: Container(
              decoration: context.appDecoration.panelBox(context, offset: 0),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ParamsTab(tabId: widget.tabId),
                  _HeadersTab(tabId: widget.tabId),
                  _BodyTab(controller: widget.bodyController),
                  ResponseSection(
                    tabId: widget.tabId,
                    responseController: widget.responseController,
                    showMetadata: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedTabBar extends StatelessWidget {
  final TabController controller;
  final ThemeData theme;
  final AppLayout layout;
  const _UnifiedTabBar({required this.controller, required this.theme, required this.layout});

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      dividerColor: Colors.transparent,
      isScrollable: true,
      indicator: BoxDecoration(
        color: theme.primaryColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: layout.borderThick),
          left: BorderSide(color: theme.dividerColor, width: layout.borderThick),
          right: BorderSide(color: theme.dividerColor, width: layout.borderThick),
        ),
      ),
      labelColor: theme.colorScheme.onPrimary,
      unselectedLabelColor: theme.colorScheme.onSurface,
      labelStyle: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.displayWeight),
      tabs: const [
        Tab(text: 'PARAMS'),
        Tab(text: 'HEADERS'),
        Tab(text: 'BODY'),
        Tab(text: 'RESPONSE'),
      ],
    );
  }
}

class _StatusRibbon extends StatelessWidget {
  final String tabId;
  const _StatusRibbon({required this.tabId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return p?.statusCode != n?.statusCode ||
            p?.durationMs != n?.durationMs ||
            p?.isSending != n?.isSending;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        final hasStatus = tab.statusCode != null || tab.durationMs != null;
        if (!hasStatus && !tab.isSending) return const SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(bottom: layout.isCompact ? 6 : 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (tab.isSending)
                _Pill(label: 'SENDING', color: theme.colorScheme.secondary)
              else ...[
                if (tab.statusCode != null)
                  _Pill(label: tab.statusCode.toString(), color: context.appPalette.statusAccent(tab.statusCode!)),
                if (tab.durationMs != null)
                  _Pill(label: '${tab.durationMs} ms', color: theme.colorScheme.secondary),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: layout.badgePaddingHorizontal, vertical: layout.badgePaddingVertical),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeNormal,
        ),
      ),
    );
  }
}

class _ParamsTab extends StatelessWidget {
  final String tabId;
  const _ParamsTab({required this.tabId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return p?.config.url != n?.config.url;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        return QueryParamsEditor(
          items: tab.config.params,
          onChanged: (list) {
            final current = context.read<TabsBloc>().state.tabs.byId(tabId);
            if (current == null) return;
            context.read<TabsBloc>().add(UpdateTab(
              current.copyWith(config: current.config.copyWith(params: list)),
            ));
          },
        );
      },
    );
  }
}

class _HeadersTab extends StatelessWidget {
  final String tabId;
  const _HeadersTab({required this.tabId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        if (p == null || n == null) return true;
        return p.config.headers.length != n.config.headers.length ||
            p.config.headers.entries.any((e) => n.config.headers[e.key] != e.value);
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        return HeadersEditor(
          items: tab.config.headers,
          onChanged: (map) {
            final current = context.read<TabsBloc>().state.tabs.byId(tabId);
            if (current == null) return;
            context.read<TabsBloc>().add(UpdateTab(
              current.copyWith(config: current.config.copyWith(headers: map)),
            ));
          },
        );
      },
    );
  }
}

class _BodyTab extends StatelessWidget {
  final CodeLineEditingController controller;
  const _BodyTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return Stack(
      children: [
        JsonCodeEditor(controller: controller),
        Positioned(
          top: 8,
          right: 8,
          child: context.appDecoration.wrapInteractive(
            child: IconButton(
              icon: Icon(Icons.auto_fix_high, color: theme.colorScheme.secondary, size: layout.isCompact ? 20 : 24),
              tooltip: 'Beautify JSON',
              onPressed: () async {
                final prettified = await JsonUtils.prettify(controller.text);
                controller.text = prettified;
              },
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/features/chaining/presentation/widgets/rules_tab_view.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/auth_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart'
    show RequestConfigSection;
import 'package:getman/features/tabs/presentation/widgets/request_editor_tabs.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_history_timeline.dart';
import 'package:getman/features/tabs/presentation/widgets/response_area.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart'
    show ResponseSection;
import 'package:re_editor/re_editor.dart';

/// Narrow-width alternative to [RequestConfigSection] + [ResponseSection].
///
/// Collapses the split-pane editor into a single four-tab strip
/// (PARAMS / HEADERS / BODY / RESPONSE). Status metadata sits above the tab
/// strip so it stays visible on every tab. Auto-focuses the RESPONSE tab when
/// a send completes.
class UnifiedRequestPanel extends StatefulWidget {
  const UnifiedRequestPanel({
    required this.tabId,
    required this.bodyController,
    required this.responseController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController bodyController;
  final CodeLineEditingController responseController;

  @override
  State<UnifiedRequestPanel> createState() => _UnifiedRequestPanelState();
}

class _UnifiedRequestPanelState extends State<UnifiedRequestPanel>
    with SingleTickerProviderStateMixin {
  static const int _responseTabIndex = 5;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final p = prev.tabs.byId(widget.tabId);
        final n = next.tabs.byId(widget.tabId);
        // Send completed: isSending flipped true → false AND we have a
        // response.
        return p?.isSending == true &&
            n?.isSending == false &&
            n?.response != null;
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
          BrandedTabBar(
            controller: _tabController,
            labels: const [
              'PARAMS',
              'AUTH',
              'HEADERS',
              'BODY',
              'RULES',
              'RESPONSE',
            ],
            isScrollable: true,
          ),
          Expanded(
            child: context.appDecoration.frost(
              context,
              borderRadius: BorderRadius.circular(context.appShape.panelRadius),
              child: Container(
                decoration: context.appDecoration.panelBox(context, offset: 0),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ParamsTabView(tabId: widget.tabId),
                    AuthTabView(tabId: widget.tabId),
                    HeadersTabView(tabId: widget.tabId),
                    BodyTabView(
                      tabId: widget.tabId,
                      controller: widget.bodyController,
                    ),
                    RulesTabView(
                      key: ValueKey('rules_${widget.tabId}'),
                      tabId: widget.tabId,
                    ),
                    ResponseArea(
                      tabId: widget.tabId,
                      responseController: widget.responseController,
                      showMetadata: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRibbon extends StatelessWidget {
  const _StatusRibbon({required this.tabId});
  final String tabId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return p?.response != n?.response ||
            p?.isSending != n?.isSending ||
            p?.responseHistory.length != n?.responseHistory.length;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        final response = tab.response;
        if (response == null && !tab.isSending) return const SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(bottom: layout.isCompact ? 6 : 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (tab.isSending)
                _Pill(label: 'SENDING', color: theme.colorScheme.secondary)
              else if (response != null) ...[
                _Pill(
                  label: response.statusCode.toString(),
                  color: context.appPalette.statusAccent(response.statusCode),
                ),
                _Pill(
                  label: '${response.durationMs} ms',
                  color: theme.colorScheme.secondary,
                ),
                _Pill(
                  label: formatBytes(responseSizeBytes(response)),
                  color: theme.colorScheme.secondary,
                ),
                ResponseHistoryTimeline(
                  tabId: tabId,
                  history: tab.responseHistory,
                  current: response,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          // Luminance-based contrast against the variable pill color (a11y).
          color: context.appPalette.onColor(color),
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeNormal,
        ),
      ),
    );
  }
}

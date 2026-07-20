// Split-pane request editor: PARAMS/AUTH/HEADERS/BODY/RULES tab strip, shown
// beside ResponseSection on wide layouts. The strip's selection is
// workspace-global (RequestSectionIndex), two-way synced per instance.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/features/chaining/presentation/widgets/rules_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/auth_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/body_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/headers_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/params_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart'
    show UnifiedRequestPanel;
import 'package:re_editor/re_editor.dart';

/// Split-pane request editor: PARAMS / HEADERS / BODY tab strip. The phone
/// layout's [UnifiedRequestPanel] composes the same tab views plus RESPONSE.
///
/// The strip's selection is workspace-global ([RequestSectionIndex]), not
/// per-request-tab: every live instance keeps its own [TabController] two-way
/// synced with the shared notifier, so switching request tabs keeps the same
/// section focused.
class RequestConfigSection extends StatefulWidget {
  const RequestConfigSection({
    required this.tabId,
    required this.bodyController,
    required this.variablesController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController bodyController;
  final CodeLineEditingController variablesController;

  @override
  State<RequestConfigSection> createState() => _RequestConfigSectionState();
}

class _RequestConfigSectionState extends State<RequestConfigSection>
    with SingleTickerProviderStateMixin {
  static const int _sectionCount = 5;

  late final TabController _tabController;
  late final RequestSectionIndex _sectionIndex;

  @override
  void initState() {
    super.initState();
    _sectionIndex = context.read<RequestSectionIndex>();
    _tabController = TabController(
      length: _sectionCount,
      vsync: this,
      initialIndex: _sectionIndex.value.clamp(0, _sectionCount - 1),
    )..addListener(_onTabChanged);
    _sectionIndex.addListener(_onSectionIndexChanged);
  }

  @override
  void dispose() {
    _sectionIndex.removeListener(_onSectionIndexChanged);
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Same-value writes are dropped by ValueNotifier, so the echo from
    // _onSectionIndexChanged's own jump can't loop.
    _sectionIndex.value = _tabController.index;
  }

  /// Another request tab's strip picked a section — jump (no animation: this
  /// instance is usually offstage with tickers disabled when it happens).
  void _onSectionIndexChanged() {
    if (_sectionIndex.value != _tabController.index) {
      _tabController.index = _sectionIndex.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrandedTabBar(
          controller: _tabController,
          labels: const ['PARAMS', 'AUTH', 'HEADERS', 'BODY', 'RULES'],
          isScrollable: true,
          tabKeyPrefix: 'reqtab',
        ),
        Expanded(
          child: context.appDecoration.frost(
            context,
            borderRadius: BorderRadius.circular(context.appShape.panelRadius),
            child: context.appComponents.surface(
              context,
              child: TabBarView(
                controller: _tabController,
                children: [
                  ParamsTabView(tabId: widget.tabId),
                  AuthTabView(tabId: widget.tabId),
                  HeadersTabView(tabId: widget.tabId),
                  BodyTabView(
                    tabId: widget.tabId,
                    controller: widget.bodyController,
                    variablesController: widget.variablesController,
                  ),
                  RulesTabView(
                    key: ValueKey('rules_${widget.tabId}'),
                    tabId: widget.tabId,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

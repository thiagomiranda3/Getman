import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/features/chaining/presentation/widgets/rules_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/auth_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/request_editor_tabs.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart'
    show UnifiedRequestPanel;
import 'package:re_editor/re_editor.dart';

/// Split-pane request editor: PARAMS / HEADERS / BODY tab strip. The phone
/// layout's [UnifiedRequestPanel] composes the same tab views plus RESPONSE.
class RequestConfigSection extends StatelessWidget {
  const RequestConfigSection({
    required this.tabId,
    required this.bodyController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController bodyController;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandedTabBar(
            labels: ['PARAMS', 'AUTH', 'HEADERS', 'BODY', 'RULES'],
            isScrollable: true,
          ),
          Expanded(
            child: Container(
              decoration: context.appDecoration.panelBox(context, offset: 0),
              child: TabBarView(
                children: [
                  ParamsTabView(tabId: tabId),
                  AuthTabView(tabId: tabId),
                  HeadersTabView(tabId: tabId),
                  BodyTabView(tabId: tabId, controller: bodyController),
                  RulesTabView(key: ValueKey('rules_$tabId'), tabId: tabId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

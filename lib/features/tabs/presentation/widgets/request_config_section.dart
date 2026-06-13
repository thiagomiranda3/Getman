import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/features/tabs/presentation/widgets/auth_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/request_editor_tabs.dart';
import 'package:re_editor/re_editor.dart';

/// Split-pane request editor: PARAMS / HEADERS / BODY tab strip. The phone
/// layout's [UnifiedRequestPanel] composes the same tab views plus RESPONSE.
class RequestConfigSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController bodyController;
  const RequestConfigSection({super.key, required this.tabId, required this.bodyController});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandedTabBar(
            labels: ['PARAMS', 'AUTH', 'HEADERS', 'BODY'],
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

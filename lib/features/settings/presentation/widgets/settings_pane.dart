// Shared scroll/column pane wrapper used by every settings-dialog tab
// (the four in-dialog tabs and SettingsShortcutsTab).

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

Widget settingsPane(BuildContext context, List<Widget> children) {
  final layout = context.appLayout;
  return SingleChildScrollView(
    padding: EdgeInsets.symmetric(vertical: layout.tabSpacing),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

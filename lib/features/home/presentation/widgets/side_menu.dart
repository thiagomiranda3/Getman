import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:getman/features/history/presentation/widgets/history_list.dart';
import 'package:getman/features/settings/presentation/widgets/settings_dialog.dart';

class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
        ),
        child: Column(
          children: [
            const _SideMenuHeader(),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: layout.borderThick,
                  ),
                ),
              ),
              child: const BrandedTabBar(
                labels: ['COLLECTIONS', 'HISTORY'],
                padding: EdgeInsets.zero,
                labelPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  CollectionsList(),
                  HistoryList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideMenuHeader extends StatelessWidget {
  const _SideMenuHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.headerPaddingVertical,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'GETMAN',
                style: TextStyle(
                  fontWeight: context.appTypography.displayWeight,
                  fontSize: layout.headerFontSize,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              context.appDecoration.wrapInteractive(
                child: IconButton(
                  icon: Icon(
                    Icons.create_new_folder,
                    color: theme.colorScheme.onSurface,
                    size: layout.iconSize,
                  ),
                  tooltip: 'NEW FOLDER',
                  onPressed: () => _showNewFolderDialog(context),
                ),
              ),
              context.appDecoration.wrapInteractive(
                child: IconButton(
                  icon: Icon(
                    Icons.settings,
                    color: theme.colorScheme.onSurface,
                    size: layout.iconSize,
                  ),
                  tooltip: 'SETTINGS',
                  onPressed: () => _showSettingsDialog(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showNewFolderDialog(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'NEW FOLDER',
        hintText: 'FOLDER NAME',
        confirmLabel: 'CREATE',
        onConfirm: (name) => bloc.add(AddFolder(name)),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    unawaited(SettingsDialog.show(context));
  }
}

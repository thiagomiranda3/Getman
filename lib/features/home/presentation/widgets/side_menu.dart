import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:getman/features/history/presentation/widgets/history_list.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
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
                border: Border.all(color: theme.dividerColor, width: layout.borderThick),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
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
                labelStyle: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.displayWeight,
                  overflow: TextOverflow.fade,
                ),
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                tabs: const [
                  Tab(text: 'COLLECTIONS'),
                  Tab(text: 'HISTORY'),
                ],
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
      padding: EdgeInsets.symmetric(horizontal: layout.inputPadding, vertical: layout.headerPaddingVertical),
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
                  letterSpacing: -1
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
                  icon: Icon(Icons.create_new_folder, color: theme.colorScheme.onSurface, size: layout.iconSize),
                  tooltip: 'NEW FOLDER',
                  onPressed: () => _showNewFolderDialog(context),
                ),
              ),
              context.appDecoration.wrapInteractive(
                child: IconButton(
                  icon: Icon(Icons.settings, color: theme.colorScheme.onSurface, size: layout.iconSize),
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
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('NEW FOLDER'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'FOLDER NAME'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<CollectionsBloc>().add(AddFolder(controller.text));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: context.read<SettingsBloc>(),
        child: const SettingsDialog(),
      ),
    );
  }
}

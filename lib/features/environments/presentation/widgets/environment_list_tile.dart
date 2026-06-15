import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// A single row in the environments list: name + active marker + export/delete
/// actions. Highlights when selected, and marks the active environment.
class EnvironmentListTile extends StatelessWidget {
  const EnvironmentListTile({
    required this.environment,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onExport,
    super.key,
  });
  final EnvironmentEntity environment;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
      builder: (context, settingsState) {
        final isActive =
            settingsState.settings.activeEnvironmentId == environment.id;
        return InkWell(
          onTap: onTap,
          child: Container(
            color: isSelected
                ? theme.primaryColor.withValues(alpha: 0.3)
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: layout.inputPadding,
              vertical: layout.inputPaddingVertical,
            ),
            child: Row(
              children: [
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.check_circle,
                      size: layout.smallIconSize,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                Expanded(
                  child: Text(
                    environment.name,
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: isActive
                          ? context.appTypography.titleWeight
                          : context.appTypography.bodyWeight,
                      color: theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  iconSize: layout.smallIconSize,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.file_download,
                    color: theme.colorScheme.onSurface,
                  ),
                  tooltip: 'Export environment',
                  onPressed: onExport,
                ),
                SizedBox(width: layout.tabSpacing),
                IconButton(
                  iconSize: layout.smallIconSize,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Delete environment',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

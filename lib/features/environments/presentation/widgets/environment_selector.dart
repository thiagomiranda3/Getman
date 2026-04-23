import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/environments/presentation/widgets/environments_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

const String _manageEnvironmentsValue = '__manage__';
const String _noEnvironmentValue = '__none__';

class EnvironmentSelector extends StatelessWidget {
  const EnvironmentSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EnvironmentsBloc, EnvironmentsState>(
      buildWhen: (p, n) => p.environments != n.environments,
      builder: (context, envState) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (p, n) => p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
          builder: (context, settingsState) {
            return _SelectorButton(
              environments: envState.environments,
              activeId: settingsState.settings.activeEnvironmentId,
            );
          },
        );
      },
    );
  }
}

class _SelectorButton extends StatelessWidget {
  final List<EnvironmentEntity> environments;
  final String? activeId;

  const _SelectorButton({required this.environments, required this.activeId});

  String _activeLabel() {
    if (activeId == null) return 'No Environment';
    for (final env in environments) {
      if (env.id == activeId) return env.name;
    }
    return 'No Environment';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    // Drop the active-env label on the narrowest viewports so the hamburger
    // + tab chip + + button + env selector all fit on a phone tab bar.
    final iconOnly = context.useTabSwitcher;
    return PopupMenuButton<String>(
      tooltip: 'Environment · ${_activeLabel()}',
      position: PopupMenuPosition.under,
      color: theme.colorScheme.surface,
      onSelected: (value) => _onSelected(context, value),
      itemBuilder: (popupContext) => _menuItems(popupContext),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: iconOnly ? 8 : layout.inputPadding,
          vertical: layout.inputPaddingVertical,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor, width: layout.borderThin),
          borderRadius: BorderRadius.circular(context.appShape.buttonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: layout.iconSize, color: theme.colorScheme.onSurface),
            if (!iconOnly) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  _activeLabel(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: context.appTypography.titleWeight,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: layout.smallIconSize, color: theme.colorScheme.onSurface),
            ],
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return [
      PopupMenuItem<String>(
        value: _noEnvironmentValue,
        child: Row(
          children: [
            if (activeId == null)
              Icon(Icons.check, size: layout.smallIconSize, color: theme.colorScheme.secondary)
            else
              SizedBox(width: layout.smallIconSize),
            const SizedBox(width: 6),
            const Text('No Environment'),
          ],
        ),
      ),
      if (environments.isNotEmpty) const PopupMenuDivider(),
      for (final env in environments)
        PopupMenuItem<String>(
          value: env.id,
          child: Row(
            children: [
              if (env.id == activeId)
                Icon(Icons.check, size: layout.smallIconSize, color: theme.colorScheme.secondary)
              else
                SizedBox(width: layout.smallIconSize),
              const SizedBox(width: 6),
              Flexible(child: Text(env.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: _manageEnvironmentsValue,
        child: Row(
          children: [
            Icon(Icons.tune, size: layout.smallIconSize),
            const SizedBox(width: 6),
            const Text('Manage environments…'),
          ],
        ),
      ),
    ];
  }

  void _onSelected(BuildContext context, String value) {
    if (value == _manageEnvironmentsValue) {
      EnvironmentsDialog.show(context);
      return;
    }
    if (value == _noEnvironmentValue) {
      context.read<SettingsBloc>().add(const UpdateActiveEnvironmentId(null));
      return;
    }
    context.read<SettingsBloc>().add(UpdateActiveEnvironmentId(value));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _historyLimitController;

  @override
  void initState() {
    super.initState();
    final initial = context.read<SettingsBloc>().state.settings.historyLimit;
    _historyLimitController = TextEditingController(text: initial.toString());
  }

  @override
  void dispose() {
    _historyLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (prev, next) => prev.settings != next.settings,
      builder: (context, state) {
        final settings = state.settings;
        return AlertDialog(
          title: const Text('SETTINGS'),
          content: SizedBox(
            width: layout.dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    'HISTORY LIMIT',
                    style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                  ),
                  trailing: SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: layout.inputPadding,
                          vertical: layout.inputPaddingVertical,
                        ),
                      ),
                      controller: _historyLimitController,
                      onChanged: (val) {
                        final limit = int.tryParse(val);
                        if (limit != null) {
                          context.read<SettingsBloc>().add(UpdateHistoryLimit(limit));
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(height: layout.tabSpacing),
                SwitchListTile(
                  activeThumbColor: theme.colorScheme.secondary,
                  activeTrackColor: theme.primaryColor,
                  title: Text(
                    'SAVE RESPONSE',
                    style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                  ),
                  value: settings.saveResponseInHistory,
                  onChanged: (val) => context.read<SettingsBloc>().add(UpdateSaveResponseInHistory(val)),
                ),
                const Divider(),
                SwitchListTile(
                  activeThumbColor: theme.colorScheme.secondary,
                  activeTrackColor: theme.primaryColor,
                  secondary: Icon(
                    settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    size: layout.iconSize,
                  ),
                  title: Text(
                    'DARK MODE',
                    style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                  ),
                  value: settings.isDarkMode,
                  onChanged: (val) => context.read<SettingsBloc>().add(UpdateDarkMode(val)),
                ),
                ListTile(
                  leading: Icon(Icons.palette_outlined, size: layout.iconSize),
                  title: Text(
                    'THEME',
                    style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                  ),
                  trailing: DropdownButton<String>(
                    value: settings.themeId,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final descriptor in appThemes.values)
                        DropdownMenuItem(
                          value: descriptor.id,
                          child: Text(descriptor.displayName),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        context.read<SettingsBloc>().add(UpdateThemeId(value));
                      }
                    },
                  ),
                ),
                SwitchListTile(
                  activeThumbColor: theme.colorScheme.secondary,
                  activeTrackColor: theme.primaryColor,
                  secondary: Icon(Icons.view_compact, size: layout.iconSize),
                  title: Text(
                    'COMPACT MODE',
                    style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                  ),
                  value: settings.isCompactMode,
                  onChanged: (val) => context.read<SettingsBloc>().add(UpdateCompactMode(val)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
          ],
        );
      },
    );
  }
}

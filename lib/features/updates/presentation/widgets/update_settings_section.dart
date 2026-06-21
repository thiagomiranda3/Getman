import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';

/// GENERAL-tab settings block: "check on startup" toggle + a manual
/// "Check for updates" button. Hidden on web (no desktop updater there).
class UpdateSettingsSection extends StatelessWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final layout = context.appLayout;
    final controller = context.read<UpdateController>();
    final bloc = context.read<SettingsBloc>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (p, n) =>
              p.settings.checkForUpdatesOnStartup !=
              n.settings.checkForUpdatesOnStartup,
          builder: (context, state) => ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: layout.inputPadding,
            ),
            leading: Icon(Icons.system_update, size: layout.iconSize),
            title: Text(
              'CHECK FOR UPDATES ON STARTUP',
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
            trailing: KeyedSubtree(
              key: const ValueKey('check_updates_switch'),
              child: context.appComponents.toggle(
                context,
                value: state.settings.checkForUpdatesOnStartup,
                onChanged: (v) =>
                    bloc.add(UpdateCheckForUpdatesOnStartup(enabled: v)),
              ),
            ),
            onTap: () => bloc.add(
              UpdateCheckForUpdatesOnStartup(
                enabled: !state.settings.checkForUpdatesOnStartup,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.tabSpacing,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UPDATES',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    SizedBox(height: layout.inputPaddingVertical),
                    AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => Text(
                        controller.currentVersion == null
                            ? 'Getman'
                            : 'Getman ${controller.currentVersion}',
                        style: TextStyle(fontSize: layout.fontSizeSmall),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: layout.tabSpacing),
              TextButton(
                key: const ValueKey('check_updates_button'),
                onPressed: controller.checkNow,
                child: const Text('CHECK FOR UPDATES'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

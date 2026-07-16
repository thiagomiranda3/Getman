import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';

/// Settings control for the Getman-owned git commit identity: name + email
/// used to author commits Getman makes (Review Changes / pull-rebase /
/// conflict-resolve continue), passed inline via `git -c user.name=… -c
/// user.email=…` — never written to the user's git config. Lives next to the
/// WORKSPACE settings tile since it only matters once a workspace folder is
/// git-managed. Desktop/mobile only (there is no git on web).
class GitIdentitySettingsTile extends StatefulWidget {
  const GitIdentitySettingsTile({super.key});

  @override
  State<GitIdentitySettingsTile> createState() =>
      _GitIdentitySettingsTileState();
}

class _GitIdentitySettingsTileState extends State<GitIdentitySettingsTile> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsBloc>().state.settings;
    _nameController = TextEditingController(text: s.gitUserName ?? '');
    _emailController = TextEditingController(text: s.gitUserEmail ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _update(BuildContext context, {String? name, String? email}) {
    final current = context.read<SettingsBloc>().state.settings;
    context.read<SettingsBloc>().add(
      UpdateGitIdentity(
        name: name ?? current.gitUserName,
        email: email ?? current.gitUserEmail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.tabSpacing,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: layout.iconSize),
              SizedBox(width: layout.tabSpacing),
              Text(
                'COMMIT IDENTITY',
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                ),
              ),
            ],
          ),
          SizedBox(height: layout.tabSpacing),
          if (kIsWeb)
            Text(
              'Available in the desktop/mobile app.',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            )
          else ...[
            Text(
              'Used to author commits Getman makes. Stored in Getman, never '
              'written to your git config.',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            SizedBox(height: layout.tabSpacing),
            TextField(
              key: const ValueKey('git_identity_name_field'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'YOUR NAME',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: layout.inputPadding,
                  vertical: layout.inputPaddingVertical,
                ),
              ),
              onChanged: (val) {
                final trimmed = val.trim();
                _update(context, name: trimmed.isEmpty ? null : trimmed);
              },
            ),
            SizedBox(height: layout.tabSpacing),
            TextField(
              key: const ValueKey('git_identity_email_field'),
              controller: _emailController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'YOUR EMAIL',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: layout.inputPadding,
                  vertical: layout.inputPaddingVertical,
                ),
              ),
              onChanged: (val) {
                final trimmed = val.trim();
                _update(context, email: trimmed.isEmpty ? null : trimmed);
              },
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_settings_tile.dart';
import 'package:getman/features/cookies/presentation/widgets/cookie_manager_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/widgets/client_certificate_tile.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    final bloc = context.read<SettingsBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) =>
          BlocProvider.value(value: bloc, child: const SettingsDialog()),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _historyLimitController;
  late final TextEditingController _connectTimeoutController;
  late final TextEditingController _sendTimeoutController;
  late final TextEditingController _receiveTimeoutController;
  late final TextEditingController _maxRedirectsController;
  late final TextEditingController _proxyController;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsBloc>().state.settings;
    _historyLimitController = TextEditingController(
      text: s.historyLimit.toString(),
    );
    _connectTimeoutController = TextEditingController(
      text: s.connectTimeoutMs.toString(),
    );
    _sendTimeoutController = TextEditingController(
      text: s.sendTimeoutMs.toString(),
    );
    _receiveTimeoutController = TextEditingController(
      text: s.receiveTimeoutMs.toString(),
    );
    _maxRedirectsController = TextEditingController(
      text: s.maxRedirects.toString(),
    );
    _proxyController = TextEditingController(text: s.proxyUrl ?? '');
  }

  @override
  void dispose() {
    _historyLimitController.dispose();
    _connectTimeoutController.dispose();
    _sendTimeoutController.dispose();
    _receiveTimeoutController.dispose();
    _maxRedirectsController.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (prev, next) => prev.settings != next.settings,
      builder: (context, state) {
        final settings = state.settings;
        return ResponsiveDialogScaffold(
          title: const Text('SETTINGS'),
          content: SizedBox(
            width: context.isDialogFullscreen
                ? double.infinity
                : layout.dialogWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      'HISTORY LIMIT',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
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
                            context.read<SettingsBloc>().add(
                              UpdateHistoryLimit(limit),
                            );
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
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    value: settings.saveResponseInHistory,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateSaveResponseInHistory(save: val),
                    ),
                  ),
                  SwitchListTile(
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    secondary: Icon(Icons.data_object, size: layout.iconSize),
                    title: Text(
                      'ALWAYS PRETTIFY LARGE RESPONSES',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    subtitle: Text(
                      'Format & highlight big bodies instead of plain text '
                      '(may be slow)',
                      style: TextStyle(fontSize: layout.fontSizeSmall),
                    ),
                    value: settings.alwaysPrettifyLargeResponses,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateAlwaysPrettifyLargeResponses(value: val),
                    ),
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
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    value: settings.isDarkMode,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateDarkMode(isDarkMode: val),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.palette_outlined,
                      size: layout.iconSize,
                    ),
                    title: Text(
                      'THEME',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
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
                          context.read<SettingsBloc>().add(
                            UpdateThemeId(value),
                          );
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
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    value: settings.isCompactMode,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateCompactMode(isCompactMode: val),
                    ),
                  ),
                  const Divider(),
                  _sectionHeader(context, 'NETWORK'),
                  _timeoutTile(
                    context,
                    'CONNECT TIMEOUT (ms)',
                    _connectTimeoutController,
                    UpdateConnectTimeout.new,
                  ),
                  _timeoutTile(
                    context,
                    'SEND TIMEOUT (ms)',
                    _sendTimeoutController,
                    UpdateSendTimeout.new,
                  ),
                  _timeoutTile(
                    context,
                    'RECEIVE TIMEOUT (ms)',
                    _receiveTimeoutController,
                    UpdateReceiveTimeout.new,
                  ),
                  SwitchListTile(
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    secondary: Icon(Icons.alt_route, size: layout.iconSize),
                    title: Text(
                      'FOLLOW REDIRECTS',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    value: settings.followRedirects,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateFollowRedirects(value: val),
                    ),
                  ),
                  if (settings.followRedirects)
                    _timeoutTile(
                      context,
                      'MAX REDIRECTS',
                      _maxRedirectsController,
                      UpdateMaxRedirects.new,
                    ),
                  SwitchListTile(
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    secondary: Icon(Icons.lock_outline, size: layout.iconSize),
                    title: Text(
                      'VERIFY SSL',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    value: settings.verifySsl,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateVerifySsl(value: val),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      'PROXY (host:port)',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    subtitle: Padding(
                      padding: EdgeInsets.only(top: layout.tabSpacing),
                      child: TextField(
                        controller: _proxyController,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          hintText: 'e.g. 127.0.0.1:8888',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: layout.inputPadding,
                            vertical: layout.inputPaddingVertical,
                          ),
                        ),
                        onChanged: (val) {
                          final trimmed = val.trim();
                          context.read<SettingsBloc>().add(
                            UpdateProxyUrl(trimmed.isEmpty ? null : trimmed),
                          );
                        },
                      ),
                    ),
                  ),
                  const ClientCertificateTile(),
                  ListTile(
                    leading: Icon(Icons.cookie_outlined, size: layout.iconSize),
                    title: Text(
                      'COOKIES',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => CookieManagerDialog.show(context),
                          child: const Text('MANAGE'),
                        ),
                        TextButton(
                          onPressed: () {
                            unawaited(
                              ConfirmDialog.show(
                                context,
                                title: 'Clear cookies?',
                                message:
                                    'Removes every stored cookie from the jar. '
                                    'This cannot be undone.',
                                confirmLabel: 'CLEAR',
                                onConfirm: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final store = context.read<CookieStore>();
                                  await store.clear();
                                  showAppSnackBarVia(
                                    messenger,
                                    'Cookie jar cleared',
                                  );
                                },
                              ),
                            );
                          },
                          child: const Text('CLEAR'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  _sectionHeader(context, 'COLLECTIONS'),
                  const WorkspaceSettingsTile(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.only(
        left: layout.inputPadding,
        top: layout.tabSpacing,
        bottom: layout.tabSpacing,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.displayWeight,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    );
  }

  Widget _timeoutTile(
    BuildContext context,
    String label,
    TextEditingController controller,
    SettingsEvent Function(int ms) event,
  ) {
    final layout = context.appLayout;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          fontSize: layout.fontSizeNormal,
          fontWeight: context.appTypography.titleWeight,
        ),
      ),
      trailing: SizedBox(
        width: 90,
        child: TextField(
          keyboardType: TextInputType.number,
          controller: controller,
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: layout.inputPadding,
              vertical: layout.inputPaddingVertical,
            ),
          ),
          onChanged: (val) {
            final ms = int.tryParse(val);
            if (ms != null) context.read<SettingsBloc>().add(event(ms));
          },
        ),
      ),
    );
  }
}

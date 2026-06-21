import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_settings_tile.dart';
import 'package:getman/features/cookies/presentation/widgets/cookie_manager_dialog.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/widgets/client_certificate_tile.dart';
import 'package:getman/features/updates/presentation/widgets/update_settings_section.dart';

/// Fixed width of the small numeric input boxes (history limit, timeouts, …).
const double _numberFieldWidth = 96;

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

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  static const _tabLabels = <String>[
    'GENERAL',
    'APPEARANCE',
    'NETWORK',
    'WORKSPACE',
    'SHORTCUTS',
  ];

  late final TabController _tabController;
  late final TextEditingController _historyLimitController;
  late final TextEditingController _responseHistoryLimitController;
  late final TextEditingController _connectTimeoutController;
  late final TextEditingController _sendTimeoutController;
  late final TextEditingController _receiveTimeoutController;
  late final TextEditingController _maxRedirectsController;
  late final TextEditingController _proxyController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    final s = context.read<SettingsBloc>().state.settings;
    _historyLimitController = TextEditingController(
      text: s.historyLimit.toString(),
    );
    _responseHistoryLimitController = TextEditingController(
      text: s.responseHistoryLimit.toString(),
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
    _tabController.dispose();
    _historyLimitController.dispose();
    _responseHistoryLimitController.dispose();
    _connectTimeoutController.dispose();
    _sendTimeoutController.dispose();
    _receiveTimeoutController.dispose();
    _maxRedirectsController.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final fullscreen = context.isDialogFullscreen;
    final media = MediaQuery.sizeOf(context);

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (prev, next) => prev.settings != next.settings,
      builder: (context, state) {
        final settings = state.settings;

        // Grayed separators that hug the tab strip top and bottom so the tabs
        // read as one solid bar (the buttons fill the height between the two
        // lines) rather than floating. `height` equals `thickness` so each
        // Divider is just its 1px line with no extra vertical box around it.
        final tabDivider = Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        );

        final tabbed = Column(
          children: [
            // Breathing room under the SETTINGS title before the tab bar.
            SizedBox(height: layout.tabSpacing),
            tabDivider,
            BrandedTabBar(
              controller: _tabController,
              labels: _tabLabels,
              isScrollable: true,
              tabKeyPrefix: 'settingstab',
              // The tab strip is already framed by a divider above and below; a
              // tab top border would double up against the upper divider.
              topIndicatorBorder: false,
              // Center the tabs with equal space on both sides instead of the
              // scrollable default's leading offset (which pushes them right).
              tabAlignment: TabAlignment.center,
            ),
            tabDivider,
            SizedBox(height: layout.tabSpacing),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _generalTab(context, settings),
                  _appearanceTab(context, settings),
                  _networkTab(context, settings),
                  _workspaceTab(context),
                  _shortcutsTab(context),
                ],
              ),
            ),
          ],
        );

        final content = fullscreen
            ? tabbed
            : SizedBox(
                width: math.min(layout.settingsDialogWidth, media.width),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.min(
                      layout.settingsDialogHeight,
                      media.height * 0.7,
                    ),
                  ),
                  child: tabbed,
                ),
              );

        return ResponsiveDialogScaffold(
          title: const Text('SETTINGS'),
          contentPadding: EdgeInsets.zero,
          content: content,
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

  // --- Panes -----------------------------------------------------------------

  Widget _pane(BuildContext context, List<Widget> children) {
    final layout = context.appLayout;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(vertical: layout.tabSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _generalTab(BuildContext context, SettingsEntity settings) {
    final bloc = context.read<SettingsBloc>();
    return _pane(context, [
      _SettingRow(
        title: 'HISTORY LIMIT',
        trailing: _numberField(
          context,
          _historyLimitController,
          (v) => bloc.add(UpdateHistoryLimit(v)),
          fieldKey: const ValueKey('history_limit_field'),
        ),
      ),
      _switch(
        context,
        title: 'SAVE RESPONSE',
        value: settings.saveResponseInHistory,
        onChanged: (v) => bloc.add(UpdateSaveResponseInHistory(save: v)),
      ),
      _switch(
        context,
        title: 'ALWAYS PRETTIFY LARGE RESPONSES',
        icon: Icons.data_object,
        subtitle:
            'Format & highlight big bodies instead of plain text (may be slow)',
        value: settings.alwaysPrettifyLargeResponses,
        onChanged: (v) =>
            bloc.add(UpdateAlwaysPrettifyLargeResponses(value: v)),
      ),
      _SettingRow(
        title: 'RESPONSE HISTORY (PER TAB)',
        icon: Icons.history,
        subtitle: 'Recent responses kept for time-travel (0 = off)',
        trailing: _numberField(
          context,
          _responseHistoryLimitController,
          (v) => bloc.add(UpdateResponseHistoryLimit(v)),
          fieldKey: const ValueKey('response_history_limit_field'),
        ),
      ),
      _switch(
        context,
        switchKey: const ValueKey('save_large_responses_switch'),
        title: 'SAVE LARGE RESPONSES IN HISTORY',
        icon: Icons.save_alt,
        subtitle: 'Off keeps big bodies out of history (metadata only)',
        value: settings.saveLargeResponsesInHistory,
        onChanged: (v) => bloc.add(UpdateSaveLargeResponsesInHistory(value: v)),
      ),
      const UpdateSettingsSection(),
    ]);
  }

  Widget _appearanceTab(BuildContext context, SettingsEntity settings) {
    final bloc = context.read<SettingsBloc>();
    return _pane(context, [
      _switch(
        context,
        title: 'DARK MODE',
        icon: settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
        value: settings.isDarkMode,
        onChanged: (v) => bloc.add(UpdateDarkMode(isDarkMode: v)),
      ),
      _SettingRow(
        title: 'THEME',
        icon: Icons.palette_outlined,
        trailing: DropdownButton<String>(
          key: const ValueKey('theme_dropdown'),
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
            if (value != null) bloc.add(UpdateThemeId(value));
          },
        ),
      ),
      _switch(
        context,
        title: 'COMPACT MODE',
        icon: Icons.view_compact,
        value: settings.isCompactMode,
        onChanged: (v) => bloc.add(UpdateCompactMode(isCompactMode: v)),
      ),
      _switch(
        context,
        switchKey: const ValueKey('reduce_effects_switch'),
        title: 'REDUCE VISUAL EFFECTS',
        icon: Icons.auto_awesome,
        subtitle: 'Disables backdrop blur & animations for performance',
        value: settings.reduceVisualEffects,
        onChanged: (v) => bloc.add(UpdateReduceVisualEffects(value: v)),
      ),
      _switch(
        context,
        switchKey: const ValueKey('theme_sounds_switch'),
        title: 'THEME SOUNDS',
        icon: Icons.volume_up,
        subtitle: 'Play themed sound effects on send & response',
        value: settings.enableThemeSounds,
        onChanged: (v) => bloc.add(UpdateEnableThemeSounds(value: v)),
      ),
    ]);
  }

  Widget _networkTab(BuildContext context, SettingsEntity settings) {
    final bloc = context.read<SettingsBloc>();
    final layout = context.appLayout;
    return _pane(context, [
      _SettingRow(
        title: 'CONNECT TIMEOUT (ms)',
        trailing: _numberField(
          context,
          _connectTimeoutController,
          (v) => bloc.add(UpdateConnectTimeout(v)),
        ),
      ),
      _SettingRow(
        title: 'SEND TIMEOUT (ms)',
        trailing: _numberField(
          context,
          _sendTimeoutController,
          (v) => bloc.add(UpdateSendTimeout(v)),
        ),
      ),
      _SettingRow(
        title: 'RECEIVE TIMEOUT (ms)',
        trailing: _numberField(
          context,
          _receiveTimeoutController,
          (v) => bloc.add(UpdateReceiveTimeout(v)),
          fieldKey: const ValueKey('receive_timeout_field'),
        ),
      ),
      _switch(
        context,
        title: 'FOLLOW REDIRECTS',
        icon: Icons.alt_route,
        value: settings.followRedirects,
        onChanged: (v) => bloc.add(UpdateFollowRedirects(value: v)),
      ),
      if (settings.followRedirects)
        _SettingRow(
          title: 'MAX REDIRECTS',
          trailing: _numberField(
            context,
            _maxRedirectsController,
            (v) => bloc.add(UpdateMaxRedirects(v)),
          ),
        ),
      _switch(
        context,
        title: 'VERIFY SSL',
        icon: Icons.lock_outline,
        value: settings.verifySsl,
        onChanged: (v) => bloc.add(UpdateVerifySsl(value: v)),
      ),
      _SettingRow(
        title: 'PROXY (host:port)',
        below: TextField(
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
            bloc.add(UpdateProxyUrl(trimmed.isEmpty ? null : trimmed));
          },
        ),
      ),
      const ClientCertificateTile(),
      _SettingRow(
        title: 'COOKIES',
        icon: Icons.cookie_outlined,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const ValueKey('cookies_manage_button'),
              onPressed: () => CookieManagerDialog.show(context),
              child: const Text('MANAGE'),
            ),
            TextButton(
              onPressed: () => _confirmClearCookies(context),
              child: const Text('CLEAR'),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _workspaceTab(BuildContext context) {
    return _pane(context, const [WorkspaceSettingsTile()]);
  }

  /// A read-only reference of every global keyboard shortcut, grouped by area.
  /// The displayed key glyphs follow the host platform: macOS shows the symbol
  /// keys (⌘ ⇧ ⌃), Windows/Linux spell the modifiers out (Ctrl / Shift). The
  /// bindings themselves mirror `appShortcuts` in `main.dart` — keep them in
  /// sync. Note: Next/Previous tab are Ctrl-only on every platform (no ⌘
  /// variant), so they render with the Control glyph even on macOS.
  Widget _shortcutsTab(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final mod = isMac ? '⌘' : 'Ctrl';
    final shift = isMac ? '⇧' : 'Shift';
    final ctrl = isMac ? '⌃' : 'Ctrl';

    return _pane(context, [
      _shortcutSection(context, 'REQUEST'),
      _shortcutRow(context, 'Send request', 'Send the active tab’s request', [
        mod,
        'Enter',
      ]),
      _shortcutRow(context, 'Save request', 'Save the request to its node', [
        mod,
        'S',
      ]),
      _shortcutRow(context, 'Beautify JSON', 'Format & indent the JSON body', [
        mod,
        'B',
      ]),
      _shortcutRow(context, 'Focus URL', 'Jump to the active tab’s URL field', [
        mod,
        'L',
      ]),
      _shortcutRow(
        context,
        'Command palette',
        'Fuzzy-jump to a request, environment, or theme',
        [mod, 'K'],
      ),
      _shortcutRow(
        context,
        'Switch environment',
        'Open the quick environment switcher',
        [mod, 'E'],
      ),
      _shortcutSection(context, 'TABS'),
      _shortcutRow(context, 'New tab', 'Open a new request tab', [mod, 'N']),
      _shortcutRow(context, 'Close tab', 'Close the active tab', [mod, 'W']),
      _shortcutRow(context, 'Next tab', 'Cycle to the next tab', [ctrl, 'Tab']),
      _shortcutRow(context, 'Previous tab', 'Cycle to the previous tab', [
        ctrl,
        shift,
        'Tab',
      ]),
      _shortcutRow(context, 'Jump to tab 1–9', 'Activate the Nth tab', [
        mod,
        '1–9',
      ]),
      _shortcutSection(context, 'PANELS'),
      _shortcutRow(context, 'New panel', 'Create a new panel (workspace)', [
        mod,
        shift,
        'N',
      ]),
      _shortcutRow(context, 'Next panel', 'Cycle to the next panel', [
        mod,
        shift,
        ']',
      ]),
      _shortcutRow(context, 'Previous panel', 'Cycle to the previous panel', [
        mod,
        shift,
        '[',
      ]),
      _shortcutRow(context, 'Jump to panel 1–9', 'Activate the Nth panel', [
        mod,
        shift,
        '1–9',
      ]),
    ]);
  }

  Widget _shortcutSection(BuildContext context, String label) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.inputPadding,
        layout.tabSpacing,
        layout.inputPadding,
        layout.inputPaddingVertical,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: layout.fontSizeNormal,
          fontWeight: context.appTypography.displayWeight,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _shortcutRow(
    BuildContext context,
    String title,
    String description,
    List<String> keys,
  ) {
    final layout = context.appLayout;
    return Padding(
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
                  title,
                  style: TextStyle(
                    fontSize: layout.fontSizeTitle,
                    fontWeight: context.appTypography.titleWeight,
                  ),
                ),
                SizedBox(height: layout.inputPaddingVertical),
                Text(
                  description,
                  style: TextStyle(fontSize: layout.fontSizeNormal),
                ),
              ],
            ),
          ),
          SizedBox(width: layout.tabSpacing),
          _KeyCombo(keys: keys),
        ],
      ),
    );
  }

  void _confirmClearCookies(BuildContext context) {
    unawaited(
      ConfirmDialog.show(
        context,
        title: 'Clear cookies?',
        message:
            'Removes every stored cookie from the jar. This cannot be undone.',
        confirmLabel: 'CLEAR',
        onConfirm: () async {
          final messenger = ScaffoldMessenger.of(context);
          final store = context.read<CookieStore>();
          await store.clear();
          showAppSnackBarVia(messenger, 'Cookie jar cleared');
        },
      ),
    );
  }

  // --- Row helpers -----------------------------------------------------------

  Widget _numberField(
    BuildContext context,
    TextEditingController controller,
    void Function(int) onParsed, {
    Key? fieldKey,
  }) {
    final layout = context.appLayout;
    return SizedBox(
      width: _numberFieldWidth,
      child: TextField(
        key: fieldKey,
        keyboardType: TextInputType.number,
        controller: controller,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.inputPaddingVertical,
          ),
        ),
        onChanged: (val) {
          final n = int.tryParse(val);
          if (n != null) onParsed(n);
        },
      ),
    );
  }

  Widget _switch(
    BuildContext context, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
    String? subtitle,
    Key? switchKey,
  }) {
    final layout = context.appLayout;
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: layout.inputPadding),
      leading: icon == null ? null : Icon(icon, size: layout.iconSize),
      title: Text(
        title,
        style: TextStyle(
          fontSize: layout.fontSizeNormal,
          fontWeight: context.appTypography.titleWeight,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: TextStyle(fontSize: layout.fontSizeSmall)),
      trailing: KeyedSubtree(
        key: switchKey,
        child: context.appComponents.toggle(
          context,
          value: value,
          onChanged: onChanged,
        ),
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// A single labelled settings row with a uniform vertical rhythm: a leading
/// icon + title, an optional [trailing] control on the right, an optional
/// [subtitle], and an optional full-width [below] control (e.g. the proxy
/// text field).
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.below,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
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
              if (icon != null) ...[
                Icon(icon, size: layout.iconSize),
                SizedBox(width: layout.tabSpacing),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: layout.fontSizeNormal,
                    fontWeight: context.appTypography.titleWeight,
                  ),
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: layout.tabSpacing),
                trailing!,
              ],
            ],
          ),
          if (subtitle != null) ...[
            SizedBox(height: layout.inputPaddingVertical),
            Text(subtitle!, style: TextStyle(fontSize: layout.fontSizeSmall)),
          ],
          if (below != null) ...[
            SizedBox(height: layout.tabSpacing),
            below!,
          ],
        ],
      ),
    );
  }
}

/// Renders a keyboard combo as a row of individual [_KeyCap]s (right-aligned,
/// wrapping on narrow widths).
class _KeyCombo extends StatelessWidget {
  const _KeyCombo({required this.keys});

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Wrap(
      spacing: layout.inputPaddingVertical,
      runSpacing: layout.inputPaddingVertical,
      alignment: WrapAlignment.end,
      children: [for (final key in keys) _KeyCap(label: key)],
    );
  }
}

/// A single bordered "key cap" glyph (e.g. `⌘`, `Ctrl`, `N`).
class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.appShape.inputRadius),
        border: Border.all(color: scheme.outline, width: layout.borderThin),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: context.appTypography.codeFontFamily,
          fontSize: layout.fontSizeNormal,
          fontWeight: context.appTypography.titleWeight,
        ),
      ),
    );
  }
}

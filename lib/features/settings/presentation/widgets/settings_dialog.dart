// The five-tab SETTINGS dialog (GENERAL/APPEARANCE/NETWORK/WORKSPACE/
// SHORTCUTS); SettingsDialog.show(initialTab:) deep-links a specific pane.
//
// Gotchas: numeric fields (timeouts, history limits, max redirects) commit
// on blur/submit via _NumberFieldBinding, not per keystroke -- an emptied or
// unparsable field reverts to the bloc's current value on blur. dispose()
// flushes any still-focused field's pending value, since Esc/close never
// fires blur.

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
import 'package:getman/features/settings/presentation/widgets/git_identity_settings_tile.dart';
import 'package:getman/features/settings/presentation/widgets/settings_pane.dart';
import 'package:getman/features/settings/presentation/widgets/settings_shortcuts_tab.dart';
import 'package:getman/features/updates/presentation/widgets/update_settings_section.dart';

/// Fixed width of the small numeric input boxes (history limit, timeouts, …).
const double _numberFieldWidth = 96;

/// The settings panes, in tab order. Callers deep-link a pane by passing one to
/// [SettingsDialog.show] (e.g. the Review Changes button sends a user with no
/// workspace connected straight to [SettingsTab.workspace]).
enum SettingsTab { general, appearance, network, workspace, shortcuts }

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({this.initialTab = SettingsTab.general, super.key});

  final SettingsTab initialTab;

  static Future<void> show(
    BuildContext context, {
    SettingsTab initialTab = SettingsTab.general,
  }) {
    final bloc = context.read<SettingsBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: SettingsDialog(initialTab: initialTab),
      ),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  // Order must match SettingsTab (its index selects the tab + the pane).
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

  late final FocusNode _historyLimitFocus;
  late final FocusNode _responseHistoryLimitFocus;
  late final FocusNode _connectTimeoutFocus;
  late final FocusNode _sendTimeoutFocus;
  late final FocusNode _receiveTimeoutFocus;
  late final FocusNode _maxRedirectsFocus;

  // Numeric settings fields commit on blur/submit (not per keystroke) — see
  // `_onNumberFieldFocusChange`. Each binding pairs a field's controller +
  // focus node with a value selector (to revert/echo the current effective
  // value) and the dispatcher for its Update event.
  late final List<_NumberFieldBinding> _numberFieldBindings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabLabels.length,
      initialIndex: widget.initialTab.index,
      vsync: this,
    );
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

    _historyLimitFocus = FocusNode();
    _responseHistoryLimitFocus = FocusNode();
    _connectTimeoutFocus = FocusNode();
    _sendTimeoutFocus = FocusNode();
    _receiveTimeoutFocus = FocusNode();
    _maxRedirectsFocus = FocusNode();

    _numberFieldBindings = [
      _NumberFieldBinding(
        controller: _historyLimitController,
        focusNode: _historyLimitFocus,
        valueOf: (s) => s.historyLimit,
        dispatch: (bloc, v) => bloc.add(UpdateHistoryLimit(v)),
      ),
      _NumberFieldBinding(
        controller: _responseHistoryLimitController,
        focusNode: _responseHistoryLimitFocus,
        valueOf: (s) => s.responseHistoryLimit,
        dispatch: (bloc, v) => bloc.add(UpdateResponseHistoryLimit(v)),
      ),
      _NumberFieldBinding(
        controller: _connectTimeoutController,
        focusNode: _connectTimeoutFocus,
        valueOf: (s) => s.connectTimeoutMs,
        dispatch: (bloc, v) => bloc.add(UpdateConnectTimeout(v)),
      ),
      _NumberFieldBinding(
        controller: _sendTimeoutController,
        focusNode: _sendTimeoutFocus,
        valueOf: (s) => s.sendTimeoutMs,
        dispatch: (bloc, v) => bloc.add(UpdateSendTimeout(v)),
      ),
      _NumberFieldBinding(
        controller: _receiveTimeoutController,
        focusNode: _receiveTimeoutFocus,
        valueOf: (s) => s.receiveTimeoutMs,
        dispatch: (bloc, v) => bloc.add(UpdateReceiveTimeout(v)),
      ),
      _NumberFieldBinding(
        controller: _maxRedirectsController,
        focusNode: _maxRedirectsFocus,
        valueOf: (s) => s.maxRedirects,
        dispatch: (bloc, v) => bloc.add(UpdateMaxRedirects(v)),
      ),
    ];
    for (final binding in _numberFieldBindings) {
      binding.focusNode.addListener(() => _onNumberFieldFocusChange(binding));
    }
  }

  // Captured for dispose-time commits: `context.read` is not usable once the
  // element is deactivated, but closing the dialog with a number field still
  // focused (Esc, the close button) must not silently drop the typed value —
  // blur never fires on that path.
  SettingsBloc? _settingsBloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsBloc = context.read<SettingsBloc>();
  }

  @override
  void dispose() {
    final bloc = _settingsBloc;
    if (bloc != null) {
      for (final binding in _numberFieldBindings) {
        if (!binding.focusNode.hasFocus) continue;
        final parsed = int.tryParse(binding.controller.text.trim());
        if (parsed != null && parsed != binding.valueOf(bloc.state.settings)) {
          binding.dispatch(bloc, parsed);
        }
      }
    }
    _tabController.dispose();
    _historyLimitController.dispose();
    _responseHistoryLimitController.dispose();
    _connectTimeoutController.dispose();
    _sendTimeoutController.dispose();
    _receiveTimeoutController.dispose();
    _maxRedirectsController.dispose();
    _proxyController.dispose();
    _historyLimitFocus.dispose();
    _responseHistoryLimitFocus.dispose();
    _connectTimeoutFocus.dispose();
    _sendTimeoutFocus.dispose();
    _receiveTimeoutFocus.dispose();
    _maxRedirectsFocus.dispose();
    super.dispose();
  }

  // Fires on every focus change (gain + loss); only loss commits. Typing
  // itself no longer dispatches — see `_numberField`'s onSubmitted, which
  // unfocuses to funnel through this same path.
  void _onNumberFieldFocusChange(_NumberFieldBinding binding) {
    if (binding.focusNode.hasFocus) return;
    final bloc = context.read<SettingsBloc>();
    final parsed = int.tryParse(binding.controller.text.trim());
    if (parsed != null) {
      binding.dispatch(bloc, parsed);
    } else {
      // Empty/unparsable: revert to the current effective value instead of
      // silently leaving stale text with nothing dispatched.
      _echoValue(binding, bloc.state.settings);
    }
  }

  void _echoValue(_NumberFieldBinding binding, SettingsEntity settings) {
    final text = binding.valueOf(settings).toString();
    if (binding.controller.text != text) binding.controller.text = text;
  }

  // Reflects the bloc's current (already-clamped) values back into any
  // number field that isn't focused right now — e.g. after a commit clamps
  // an out-of-range value, or after any other settings change. Fields being
  // actively typed into are left alone so we never clobber in-progress input.
  void _syncNumberFields(SettingsEntity settings) {
    for (final binding in _numberFieldBindings) {
      if (binding.focusNode.hasFocus) continue;
      _echoValue(binding, settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final fullscreen = context.isDialogFullscreen;
    final media = MediaQuery.sizeOf(context);

    return BlocConsumer<SettingsBloc, SettingsState>(
      listenWhen: (prev, next) => prev.settings != next.settings,
      listener: (context, state) => _syncNumberFields(state.settings),
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
                  const SettingsShortcutsTab(),
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

  Widget _generalTab(BuildContext context, SettingsEntity settings) {
    final bloc = context.read<SettingsBloc>();
    return settingsPane(context, [
      _SettingRow(
        title: 'HISTORY LIMIT',
        trailing: _numberField(
          context,
          _historyLimitController,
          _historyLimitFocus,
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
          _responseHistoryLimitFocus,
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
    return settingsPane(context, [
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
    ]);
  }

  Widget _networkTab(BuildContext context, SettingsEntity settings) {
    final bloc = context.read<SettingsBloc>();
    final layout = context.appLayout;
    return settingsPane(context, [
      _SettingRow(
        title: 'CONNECT TIMEOUT (ms)',
        trailing: _numberField(
          context,
          _connectTimeoutController,
          _connectTimeoutFocus,
        ),
      ),
      _SettingRow(
        title: 'SEND TIMEOUT (ms)',
        trailing: _numberField(
          context,
          _sendTimeoutController,
          _sendTimeoutFocus,
        ),
      ),
      _SettingRow(
        title: 'RECEIVE TIMEOUT (ms)',
        trailing: _numberField(
          context,
          _receiveTimeoutController,
          _receiveTimeoutFocus,
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
            _maxRedirectsFocus,
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
    return settingsPane(context, const [
      WorkspaceSettingsTile(),
      GitIdentitySettingsTile(),
    ]);
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

  // Commits on blur/submit, not per keystroke — a partial or transient
  // keystroke (e.g. "5" while typing "50") must never reach the bloc, since
  // some fields (history limit, live timeouts) take effect immediately on
  // dispatch. `onSubmitted` unfocuses so the actual commit funnels through
  // the single `_onNumberFieldFocusChange` path (see initState).
  Widget _numberField(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode, {
    Key? fieldKey,
  }) {
    final layout = context.appLayout;
    return SizedBox(
      width: _numberFieldWidth,
      child: TextField(
        key: fieldKey,
        keyboardType: TextInputType.number,
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.inputPaddingVertical,
          ),
        ),
        onSubmitted: (_) => focusNode.unfocus(),
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
    // A transparency Material gives the row its own ink surface. Under the
    // glass theme the dialog wraps its content in a frosted card (a colored
    // DecoratedBox); Flutter 3.44 asserts when a ListTile's nearest background
    // ancestor is that colored box rather than a Material.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
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
      ),
    );
  }
}

/// Pairs a numeric settings field's [controller] + [focusNode] with a
/// [valueOf] selector (reads the field's current effective value off
/// [SettingsEntity], used to revert an emptied field or echo back a clamped
/// commit) and its [dispatch]er (fires the field's `Update*` event). See
/// `_SettingsDialogState._onNumberFieldFocusChange`.
class _NumberFieldBinding {
  const _NumberFieldBinding({
    required this.controller,
    required this.focusNode,
    required this.valueOf,
    required this.dispatch,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int Function(SettingsEntity settings) valueOf;
  final void Function(SettingsBloc bloc, int value) dispatch;
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

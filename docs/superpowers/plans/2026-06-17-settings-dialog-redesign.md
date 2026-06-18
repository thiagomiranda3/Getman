# Settings Dialog Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single long-scroll Settings dialog into a wider, four-tab dialog (GENERAL / APPEARANCE / NETWORK / WORKSPACE) with consistent row spacing, without changing any setting's behavior.

**Architecture:** A horizontal `BrandedTabBar` + `TabBarView` inside the existing `ResponsiveDialogScaffold` (centered `AlertDialog` > 700 px, full-screen `Scaffold` ≤ 700 px). Width/height come from two new `AppLayout` fields; the modal branch bounds the `TabBarView` with a `SizedBox`+`ConstrainedBox`, the full-screen branch lets it fill the Scaffold body. A private `_SettingRow` + `_switch` helper give every row a uniform vertical rhythm.

**Tech Stack:** Flutter, `flutter_bloc`, `very_good_analysis` + `custom_lint` + `bloc_lint`, `flutter_test` (widget) and `patrol_finders` (macOS E2E). Invoke Flutter as `fvm flutter ...`.

## Global Constraints

- Flutter is pinned — always `fvm flutter ...`, never bare `flutter`.
- No hardcoded sizes/colors/radii/weights/paddings in widgets — pull from `context.appLayout` / `appTypography` / `appPalette`; new sizes go in `AppLayout`.
- Imports are `package:getman/...` (no relative); keep them alphabetically ordered (`directives_ordering`).
- Never use `Colors.black/white/red` literals outside `lib/core/theme/` (custom_lint `avoid_hardcoded_brand_colors`).
- Never `sl<T>()` / `GetIt` from a widget (custom_lint `avoid_get_it_in_widgets`).
- Preserve every existing `ValueKey` verbatim: `history_limit_field`, `response_history_limit_field`, `receive_timeout_field`, `theme_dropdown`, `save_large_responses_switch`, `reduce_effects_switch`, `cookies_manage_button`.
- Done-bar (run all, expect zero issues): `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test tools` clean, `fvm flutter test` green. E2E (`bash integration_test/run_macos.sh`) green on macOS.
- Spec: `docs/superpowers/specs/2026-06-17-settings-dialog-redesign-design.md`.

---

## File Structure

- **Modify** `lib/core/theme/extensions/app_layout.dart` — add `settingsDialogWidth` + `settingsDialogHeight` (fields, ctor, `copyWith`, `lerp`, `normal`, `compact`).
- **Create** `test/core/theme/app_layout_test.dart` — guards the two new fields through `copyWith`/`lerp`.
- **Rewrite** `lib/features/settings/presentation/widgets/settings_dialog.dart` — tabbed layout + `_SettingRow`/`_switch`/`_numberField` helpers.
- **Create** `test/features/settings/presentation/widgets/settings_dialog_test.dart` — widget test: four tabs, tab-switch reveals the right controls (fast, no macOS).
- **Modify** `integration_test/support/actions.dart` — add `openSettingsTab`; make `setTheme` + `toggleSettingRow` select the APPEARANCE tab.
- **Modify** E2E flows: `settings_test.dart`, `settings_network_test.dart`, `theme_stress_test.dart`, `extras_test.dart`, `cookies_test.dart`, `responsive_test.dart`.
- **Create** `integration_test/flows/settings_tabs_test.dart` + register in `integration_test/all_flows_test.dart`.
- **Modify** `integration_test/BACKLOG.md` (a "Covered" bullet) and the GitHub wiki Settings page.

---

## Task 1: AppLayout — settings dialog width & height

**Files:**
- Modify: `lib/core/theme/extensions/app_layout.dart`
- Test: `test/core/theme/app_layout_test.dart`

**Interfaces:**
- Produces: `AppLayout.settingsDialogWidth` (double) and `AppLayout.settingsDialogHeight` (double); `AppLayout.normal` = 600/520, `AppLayout.compact` = 480/440. Read in Task 2 via `context.appLayout.settingsDialogWidth` / `.settingsDialogHeight`.

- [ ] **Step 1: Write the failing test** — create `test/core/theme/app_layout_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_layout.dart';

void main() {
  test('settings dialog sizes differ between normal and compact', () {
    expect(AppLayout.normal.settingsDialogWidth, 600);
    expect(AppLayout.normal.settingsDialogHeight, 520);
    expect(AppLayout.compact.settingsDialogWidth, 480);
    expect(AppLayout.compact.settingsDialogHeight, 440);
  });

  test('copyWith overrides the settings dialog sizes', () {
    final l = AppLayout.normal.copyWith(
      settingsDialogWidth: 700,
      settingsDialogHeight: 600,
    );
    expect(l.settingsDialogWidth, 700);
    expect(l.settingsDialogHeight, 600);
    expect(l.dialogWidth, AppLayout.normal.dialogWidth); // unrelated field kept
  });

  test('lerp reaches the target endpoint at t=1', () {
    final lerped = AppLayout.compact.lerp(AppLayout.normal, 1) as AppLayout;
    expect(lerped.settingsDialogWidth, AppLayout.normal.settingsDialogWidth);
    expect(lerped.settingsDialogHeight, AppLayout.normal.settingsDialogHeight);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/theme/app_layout_test.dart`
Expected: FAIL to compile — `settingsDialogWidth` / `settingsDialogHeight` are not defined on `AppLayout`.

- [ ] **Step 3: Add the two fields.** In `lib/core/theme/extensions/app_layout.dart`:

  (a) In the constructor (after `required this.dialogWidth,`):
```dart
    required this.dialogWidth,
    required this.settingsDialogWidth,
    required this.settingsDialogHeight,
```
  (b) In the field declarations (after `final double dialogWidth;`):
```dart
  final double dialogWidth;

  /// Width of the Settings dialog content in the centered (modal) layout.
  final double settingsDialogWidth;

  /// Soft target height of the Settings dialog content in the modal layout;
  /// capped at 70% of the screen height by the dialog itself.
  final double settingsDialogHeight;
```
  (c) In `copyWith`'s parameter list (after `double? dialogWidth,`):
```dart
    double? dialogWidth,
    double? settingsDialogWidth,
    double? settingsDialogHeight,
```
  (d) In `copyWith`'s returned `AppLayout(...)` (after `dialogWidth: dialogWidth ?? this.dialogWidth,`):
```dart
      dialogWidth: dialogWidth ?? this.dialogWidth,
      settingsDialogWidth: settingsDialogWidth ?? this.settingsDialogWidth,
      settingsDialogHeight: settingsDialogHeight ?? this.settingsDialogHeight,
```
  (e) In `lerp`'s returned `AppLayout(...)` (after `dialogWidth: l(dialogWidth, other.dialogWidth),`):
```dart
      dialogWidth: l(dialogWidth, other.dialogWidth),
      settingsDialogWidth: l(settingsDialogWidth, other.settingsDialogWidth),
      settingsDialogHeight: l(settingsDialogHeight, other.settingsDialogHeight),
```
  (f) In `static const normal` (after `dialogWidth: 400,`):
```dart
    dialogWidth: 400,
    settingsDialogWidth: 600,
    settingsDialogHeight: 520,
```
  (g) In `static const compact` (after `dialogWidth: 320,`):
```dart
    dialogWidth: 320,
    settingsDialogWidth: 480,
    settingsDialogHeight: 440,
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `fvm flutter test test/core/theme/app_layout_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Format + analyze, then commit**

Run: `fvm dart format lib test && fvm flutter analyze`
Expected: formatter clean, analyze "No issues found!".

```bash
git add lib/core/theme/extensions/app_layout.dart test/core/theme/app_layout_test.dart
git commit -m "feat(theme): add AppLayout settingsDialogWidth/Height"
```

---

## Task 2: Tabbed settings dialog

**Files:**
- Rewrite: `lib/features/settings/presentation/widgets/settings_dialog.dart`
- Test: `test/features/settings/presentation/widgets/settings_dialog_test.dart`

**Interfaces:**
- Consumes: `AppLayout.settingsDialogWidth` / `.settingsDialogHeight` (Task 1); `BrandedTabBar(controller, labels, isScrollable, tabKeyPrefix)`; `ResponsiveDialogScaffold(title, content, actions, contentPadding)`.
- Produces: four tab `ValueKey`s `settingstab_tab_GENERAL/APPEARANCE/NETWORK/WORKSPACE`; default tab = GENERAL. All existing control keys preserved.

- [ ] **Step 1: Write the failing widget test** — create `test/features/settings/presentation/widgets/settings_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/widgets/settings_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _MockSaveSettings extends Mock implements SaveSettingsUseCase {}

SettingsBloc _bloc() {
  final save = _MockSaveSettings();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
}

Future<void> _open(WidgetTester tester, SettingsBloc bloc) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SettingsDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows four tabs; GENERAL is the default pane', (tester) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _open(tester, bloc);

    expect(find.byKey(const ValueKey('settingstab_tab_GENERAL')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settingstab_tab_APPEARANCE')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settingstab_tab_NETWORK')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settingstab_tab_WORKSPACE')),
      findsOneWidget,
    );

    // GENERAL active → history limit visible; APPEARANCE's theme dropdown not.
    expect(find.byKey(const ValueKey('history_limit_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_dropdown')), findsNothing);
  });

  testWidgets('switching tabs reveals each pane\'s controls', (tester) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _open(tester, bloc);

    await tester.tap(find.byKey(const ValueKey('settingstab_tab_APPEARANCE')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme_dropdown')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settingstab_tab_NETWORK')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receive_timeout_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('cookies_manage_button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settingstab_tab_WORKSPACE')));
    await tester.pumpAndSettle();
    expect(find.text('CHOOSE FOLDER'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/features/settings/presentation/widgets/settings_dialog_test.dart`
Expected: FAIL — no `settingstab_tab_*` keys exist (current dialog has no tabs); the `theme_dropdown`-not-visible assertion also fails because today everything is in one scroll view.

- [ ] **Step 3: Rewrite the dialog.** Replace the entire contents of `lib/features/settings/presentation/widgets/settings_dialog.dart` with:

```dart
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

        final tabbed = Column(
          children: [
            BrandedTabBar(
              controller: _tabController,
              labels: _tabLabels,
              isScrollable: true,
              tabKeyPrefix: 'settingstab',
            ),
            SizedBox(height: layout.tabSpacing),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _generalTab(context, settings),
                  _appearanceTab(context, settings),
                  _networkTab(context, settings),
                  _workspaceTab(context),
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
        onChanged: (v) => bloc.add(UpdateAlwaysPrettifyLargeResponses(value: v)),
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
    return SwitchListTile(
      key: switchKey,
      contentPadding: EdgeInsets.symmetric(horizontal: layout.inputPadding),
      secondary: icon == null ? null : Icon(icon, size: layout.iconSize),
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
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A single labelled settings row with a uniform vertical rhythm: a leading
/// icon + title, an optional [trailing] control on the right, an optional
/// [subtitle], and an optional full-width [below] control (text fields).
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
```

- [ ] **Step 4: Run the widget test, verify it passes**

Run: `fvm flutter test test/features/settings/presentation/widgets/settings_dialog_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Full local gate**

Run:
```
fvm dart format lib test
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```
Expected: formatter clean; analyze, custom_lint, bloc_lint each report no issues; full unit/widget suite green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/presentation/widgets/settings_dialog.dart test/features/settings/presentation/widgets/settings_dialog_test.dart
git commit -m "feat(settings): tabbed, wider settings dialog with consistent spacing"
```

---

## Task 3: E2E — helper, flow adjustments, and a new tab-navigation flow

**Files:**
- Modify: `integration_test/support/actions.dart`
- Modify: `integration_test/flows/settings_test.dart`, `settings_network_test.dart`, `theme_stress_test.dart`, `extras_test.dart`, `cookies_test.dart`, `responsive_test.dart`
- Create: `integration_test/flows/settings_tabs_test.dart`
- Modify: `integration_test/all_flows_test.dart`

**Interfaces:**
- Consumes: the `settingstab_tab_*` keys from Task 2; existing helpers `openSettings`, `pumpFrames`, `slowMo`, `bootGetman`.
- Produces: `openSettingsTab(PatrolTester $, String label)`.

- [ ] **Step 1: Add the `openSettingsTab` helper.** In `integration_test/support/actions.dart`, immediately after the `openSettings` function (ends at the line with `await slowMo($); }`), add:

```dart
/// Taps a Settings dialog tab by its [label]
/// (`GENERAL`/`APPEARANCE`/`NETWORK`/`WORKSPACE`). Assumes Settings is open.
/// Animation-safe (themes may animate forever, so no `pumpAndSettle`).
Future<void> openSettingsTab(PatrolTester $, String label) async {
  await $(
    ValueKey('settingstab_tab_$label'),
  ).tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await slowMo($);
}
```

- [ ] **Step 2: Make the shared theme/toggle helpers select APPEARANCE.** In the same file:

  In `setTheme`, change the opening:
```dart
Future<void> setTheme(PatrolTester $, String displayName) async {
  await openSettings($);
  await openSettingsTab($, 'APPEARANCE');
  await $(
    const ValueKey('theme_dropdown'),
  ).tap(settlePolicy: SettlePolicy.noSettle);
```
  In `toggleSettingRow`, change the opening:
```dart
Future<void> toggleSettingRow(PatrolTester $, String label) async {
  await openSettings($);
  await openSettingsTab($, 'APPEARANCE');
  await $(label).tap(settlePolicy: SettlePolicy.noSettle);
```
  (Every current caller of `toggleSettingRow` targets an APPEARANCE row: `DARK MODE`, `COMPACT MODE`. `setTheme` only touches `theme_dropdown`, also APPEARANCE.)

- [ ] **Step 3: Adjust `flows/settings_test.dart`.**

  *switches the active theme* — after `await openSettings($);`, insert `await openSettingsTab($, 'APPEARANCE');` (before `expect($('BRUTALIST'), findsWidgets);`).
  *toggles dark mode* — after `await openSettings($);`, insert `await openSettingsTab($, 'APPEARANCE');`.

- [ ] **Step 4: Adjust `flows/settings_network_test.dart`.**

  *receive timeout aborts a slow response* — after `await openSettings($);`, insert `await openSettingsTab($, 'NETWORK');` (before `await $(const ValueKey('receive_timeout_field')).enterText('500');`).
  *history limit trims older entries* — **no change** (`history_limit_field` is on the default GENERAL tab).

- [ ] **Step 5: Adjust `flows/theme_stress_test.dart`.**

  In *LIQUID GLASS reduce-effects toggled repeatedly is stable*, after `await openSettings($);` and before the `for` loop, insert:
```dart
    await openSettingsTab($, 'APPEARANCE');
```

- [ ] **Step 6: Adjust `flows/extras_test.dart` (clear cookies).**

  After `await openSettings($);` (the one preceding `final clearButton = find.text('CLEAR');`), insert:
```dart
    await openSettingsTab($, 'NETWORK');
```
  (Keep the existing `ensureVisible(clearButton)` — the NETWORK pane scrolls.)

- [ ] **Step 7: Adjust `flows/cookies_test.dart`.**

  After `await openSettings($);` (preceding `final manageButton = find.byKey(const ValueKey('cookies_manage_button'));`), insert:
```dart
    await openSettingsTab($, 'NETWORK');
```

- [ ] **Step 8: Extend `flows/responsive_test.dart` (resizing while a dialog is open).**

  After `expect($('SETTINGS'), findsWidgets);` (the first one, right after `openSettings`), add:
```dart
    expect($(const ValueKey('settingstab_tab_GENERAL')), findsWidgets);
    expect($(const ValueKey('history_limit_field')), findsWidgets);
```
  After the shrink-to-phone resize block (`await resizeWindow($, const Size(620, 900));` then `expect($('SETTINGS'), findsWidgets);`), add:
```dart
    // Full-screen dialog keeps the tab strip + GENERAL pane (no overflow).
    expect($(const ValueKey('settingstab_tab_GENERAL')), findsWidgets);
```

- [ ] **Step 9: Create `flows/settings_tabs_test.dart`:**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// The redesigned Settings dialog groups controls under four tabs
/// (GENERAL / APPEARANCE / NETWORK / WORKSPACE). Verify the tabs exist and that
/// switching reveals the right controls — on desktop (modal) and at phone width
/// (full-screen page).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('navigates the four settings tabs', ($) async {
    await bootGetman($);
    await openSettings($);

    expect($(const ValueKey('settingstab_tab_GENERAL')), findsWidgets);
    expect($(const ValueKey('settingstab_tab_APPEARANCE')), findsWidgets);
    expect($(const ValueKey('settingstab_tab_NETWORK')), findsWidgets);
    expect($(const ValueKey('settingstab_tab_WORKSPACE')), findsWidgets);

    // GENERAL is the default tab.
    expect($(const ValueKey('history_limit_field')), findsWidgets);

    await openSettingsTab($, 'APPEARANCE');
    expect($(const ValueKey('theme_dropdown')), findsWidgets);

    await openSettingsTab($, 'NETWORK');
    expect($(const ValueKey('receive_timeout_field')), findsWidgets);
    expect($(const ValueKey('cookies_manage_button')), findsWidgets);

    await openSettingsTab($, 'WORKSPACE');
    expect($('CHOOSE FOLDER'), findsWidgets);

    await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);
  });

  patrolWidgetTest('switches tabs at phone width (full-screen)', ($) async {
    await bootGetman($, windowSize: const Size(640, 920));
    await openSettings($);

    expect($(const ValueKey('settingstab_tab_NETWORK')), findsWidgets);
    await openSettingsTab($, 'NETWORK');
    expect($('VERIFY SSL'), findsWidgets);

    await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);
  });
}
```

- [ ] **Step 10: Register the new flow in `integration_test/all_flows_test.dart`.**

  Add the import after line 33 (`import 'flows/settings_network_test.dart' as settings_network;`):
```dart
import 'flows/settings_tabs_test.dart' as settings_tabs;
```
  Add the call after `settings_network.main();` (currently line 88):
```dart
  settings_tabs.main();
```

- [ ] **Step 11: Run the new + adjusted flows on macOS.** (Each builds & launches the real macOS app; run them individually.)

Run:
```
bash integration_test/run_macos.sh settings_tabs
bash integration_test/run_macos.sh settings
bash integration_test/run_macos.sh settings_network
bash integration_test/run_macos.sh cookies
bash integration_test/run_macos.sh extras
bash integration_test/run_macos.sh theme_stress
bash integration_test/run_macos.sh responsive
```
Expected: all green. (If the sandbox can't build/launch the macOS app, note it and have the maintainer run `bash integration_test/run_macos.sh` once before merge — the widget test in Task 2 plus the static gate are the in-sandbox signal.)

- [ ] **Step 12: Re-run the static gate + commit.**

Run: `fvm dart format integration_test && fvm flutter analyze`
Expected: clean.

```bash
git add integration_test/support/actions.dart integration_test/flows/settings_test.dart integration_test/flows/settings_network_test.dart integration_test/flows/theme_stress_test.dart integration_test/flows/extras_test.dart integration_test/flows/cookies_test.dart integration_test/flows/responsive_test.dart integration_test/flows/settings_tabs_test.dart integration_test/all_flows_test.dart
git commit -m "test(settings): tab-aware E2E helpers + settings_tabs flow"
```

---

## Task 4: Docs — BACKLOG bullet + wiki sync

**Files:**
- Modify: `integration_test/BACKLOG.md`
- Modify: GitHub wiki Settings page (separate `Getman.wiki.git` repo)

- [ ] **Step 1: Add a covered bullet to `integration_test/BACKLOG.md`** under the "Covered (deep)" list (next to the existing Settings entry), e.g.:

```markdown
- **Settings tabs** — `settings_tabs_test` (four-tab dialog: navigate
  GENERAL/APPEARANCE/NETWORK/WORKSPACE on desktop + at phone width).
```

- [ ] **Step 2: Update the wiki Settings page.** Clone (if not already present) and edit:

```bash
cd /tmp && rm -rf Getman.wiki && git clone https://github.com/thiagomiranda3/Getman.wiki.git Getman.wiki
```
  Open the Settings page markdown (e.g. `Settings.md`) and describe the four tabs with their verbatim labels — **GENERAL** (history limit, save response, prettify large responses, response history per tab, save large responses), **APPEARANCE** (dark mode, theme, compact mode, reduce visual effects), **NETWORK** (timeouts, follow redirects, max redirects, verify SSL, proxy, client certificate, cookies), **WORKSPACE** (workspace folder). Keep wording accurate to the UI.

- [ ] **Step 3: Commit both.**

```bash
cd /Users/thiago/git/getman && git add integration_test/BACKLOG.md && git commit -m "docs(e2e): note settings_tabs coverage in BACKLOG"
cd /tmp/Getman.wiki && git add -A && git commit -m "Settings: document the four-tab layout" && git push origin master
```

---

## Self-Review

**Spec coverage:**
- Tabs (4, 1:1) → Task 2 (`_tabLabels`, four pane builders). ✓
- Wider modal + new `AppLayout` fields → Task 1 + Task 2 (`settingsDialogWidth/Height`, `SizedBox`/`ConstrainedBox`). ✓
- Spacing rhythm + de-dup → Task 2 (`_SettingRow`, `_switch`, `_numberField`). ✓
- Flush tab bar (`contentPadding: EdgeInsets.zero`) → Task 2. ✓
- Responsive: scrollable tabs, width clamp, height cap, modal↔fullscreen → Task 2 + extended `responsive_test` (Task 3 Step 8). ✓
- Keys preserved + four new tab keys → Task 2; asserted in Task 2 widget test + Task 3 flow. ✓
- Helper + all flow adjustments + new flow + aggregator → Task 3 (Steps 1–10). ✓
- Wiki + BACKLOG → Task 4. ✓

**Placeholder scan:** none — every code/step is concrete.

**Type consistency:** `openSettingsTab(PatrolTester, String)` used identically in helper def and all callers; `settingstab_tab_<LABEL>` keys consistent between dialog (`tabKeyPrefix: 'settingstab'`), widget test, and flow; `settingsDialogWidth`/`settingsDialogHeight` names match across `AppLayout` and the dialog; event constructors (`UpdateSaveResponseInHistory(save:)`, `Update*(value:)`, `UpdateDarkMode(isDarkMode:)`, `UpdateCompactMode(isCompactMode:)`) match the existing events.

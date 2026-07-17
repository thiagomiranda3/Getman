// SHORTCUTS tab of the settings dialog: a static keyboard-shortcut
// cheat-sheet (sections REQUEST/TABS/PANELS/...), rendered with _KeyCap key
// caps. Purely informational — changing real bindings happens in
// main.dart's appShortcuts map.

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// A read-only reference of every global keyboard shortcut, grouped by area.
/// The displayed key glyphs follow the host platform: macOS shows the symbol
/// keys (⌘ ⇧ ⌃), Windows/Linux spell the modifiers out (Ctrl / Shift). The
/// bindings themselves mirror `appShortcuts` in `main.dart` — keep them in
/// sync. Note: Next/Previous tab are Ctrl-only on every platform (no ⌘
/// variant), so they render with the Control glyph even on macOS.
class SettingsShortcutsTab extends StatelessWidget {
  const SettingsShortcutsTab({super.key});

  @override
  Widget build(BuildContext context) {
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
}

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

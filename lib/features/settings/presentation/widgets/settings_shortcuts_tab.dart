// SHORTCUTS tab of the settings dialog: renders the single-source shortcut
// catalog (lib/core/navigation/shortcut_catalog.dart) as grouped sections
// with _KeyCap key caps. Purely informational — changing real bindings
// happens in main.dart's appShortcuts map; adding a shortcut means adding a
// catalog entry (plus the binding), not editing this widget.

import 'package:flutter/material.dart';
import 'package:getman/core/navigation/shortcut_catalog.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/settings/presentation/widgets/settings_pane.dart';

/// A read-only reference of every global keyboard shortcut, grouped by area.
/// Rows come from [shortcutCatalog] — the same source the cheat-sheet
/// overlay and tooltip hints read — so the surfaces can never drift. The
/// displayed key glyphs follow the host platform: macOS shows the symbol
/// keys (⌘ ⇧ ⌥ ⌃), Windows/Linux spell the modifiers out (Ctrl / Shift /
/// Alt). Note: Next/Previous tab are Ctrl-only on every platform (no ⌘
/// variant), so they render with the Control glyph even on macOS.
class SettingsShortcutsTab extends StatelessWidget {
  const SettingsShortcutsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final children = <Widget>[];
    String? section;
    for (final entry in shortcutCatalog(useMeta: isMac)) {
      if (entry.section != section) {
        section = entry.section;
        children.add(_shortcutSection(context, section));
      }
      children.add(
        _shortcutRow(context, entry.title, entry.description, entry.keyCaps),
      );
    }
    return settingsPane(context, children);
  }
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

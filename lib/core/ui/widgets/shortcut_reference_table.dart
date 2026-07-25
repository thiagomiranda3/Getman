// Shared read-only keyboard-shortcut reference table: one row per
// shortcutCatalog() entry, grouped under its section heading (description
// left, bordered key caps right), platform-aware via useMetaShortcuts. THE
// single rendering source for the settings SHORTCUTS tab and the
// Cmd/Ctrl+/ KEYBOARD SHORTCUTS dialog — change rendering here, never fork
// it.

import 'package:flutter/material.dart';
import 'package:getman/core/navigation/shortcut_catalog.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Renders every [shortcutCatalog] entry, grouped by section, as a row:
/// title + description on the left, the key combo as bordered key caps on
/// the right. [useMeta] overrides the platform convention (for
/// tests/previews); null follows the app-wide [useMetaShortcuts] predicate.
class ShortcutReferenceTable extends StatelessWidget {
  const ShortcutReferenceTable({this.useMeta, super.key});

  final bool? useMeta;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? section;
    for (final entry in shortcutCatalog(useMeta: useMeta ?? useMetaShortcuts)) {
      if (entry.section != section) {
        section = entry.section;
        children.add(_ShortcutSection(label: section));
      }
      children.add(
        _ShortcutRow(
          title: entry.title,
          description: entry.description,
          keys: entry.keyCaps,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ShortcutSection extends StatelessWidget {
  const _ShortcutSection({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
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
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.title,
    required this.description,
    required this.keys,
  });

  final String title;
  final String description;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
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

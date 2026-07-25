// SHORTCUTS tab of the settings dialog: a thin settingsPane wrapper around
// the shared ShortcutReferenceTable (single rendering source, also used by
// the Cmd/Ctrl+/ KEYBOARD SHORTCUTS dialog). The bindings themselves live in
// main.dart's appShortcuts; the catalog is
// lib/core/navigation/shortcut_catalog.dart.

import 'package:flutter/material.dart';
import 'package:getman/core/ui/widgets/shortcut_reference_table.dart';
import 'package:getman/features/settings/presentation/widgets/settings_pane.dart';

/// A read-only reference of every global keyboard shortcut. Rendering is
/// delegated to [ShortcutReferenceTable] so this tab and the E1 cheat-sheet
/// dialog can never drift apart.
class SettingsShortcutsTab extends StatelessWidget {
  const SettingsShortcutsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return settingsPane(context, const [ShortcutReferenceTable()]);
  }
}

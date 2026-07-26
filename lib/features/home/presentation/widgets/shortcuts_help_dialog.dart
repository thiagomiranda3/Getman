// KEYBOARD SHORTCUTS cheat-sheet dialog (Cmd/Ctrl+/): the shared
// ShortcutReferenceTable in standard app dialog chrome (same sizing pattern
// as the settings dialog). Esc closes (stock dialog behavior). Pressing
// Cmd/Ctrl+/ again ALSO closes: the root Shortcuts map above MaterialApp
// still fires ShowShortcutsIntent while this dialog holds focus, and the
// local Actions below maps it to pop. The OPEN half of that toggle is
// MainScreen's ShowShortcutsIntent action, which is a sibling route while
// this dialog is up and therefore correctly unreachable (the D8 property) —
// no double-open, no shared open/closed flag.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/ui/widgets/shortcut_reference_table.dart';

/// The Cmd/Ctrl+/ cheat sheet: every global shortcut, platform-correct, in
/// the exact table the settings SHORTCUTS tab renders.
class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  static Future<void> show(BuildContext context) => showResponsiveDialog<void>(
    context,
    builder: (_) => const ShortcutsHelpDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final media = MediaQuery.sizeOf(context);

    const table = SingleChildScrollView(child: ShortcutReferenceTable());
    final content = context.isDialogFullscreen
        ? table
        : SizedBox(
            width: math.min(layout.settingsDialogWidth, media.width),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.min(
                  layout.settingsDialogHeight,
                  media.height * 0.7,
                ),
              ),
              child: table,
            ),
          );

    return Actions(
      actions: <Type, Action<Intent>>{
        // The CLOSE half of the Cmd/Ctrl+/ toggle — see the file header.
        ShowShortcutsIntent: CallbackAction<ShowShortcutsIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: Focus(
        autofocus: true,
        child: ResponsiveDialogScaffold(
          title: const Text('KEYBOARD SHORTCUTS'),
          content: content,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      ),
    );
  }
}

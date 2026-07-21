// Blocking "DOWNLOADING UPDATE…" progress dialog for the Windows/Linux
// in-app update flow; deliberately non-dismissible — the user already
// confirmed Getman will close when the download finishes.

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

/// Modal indeterminate-progress dialog shown while the update installer
/// downloads. No actions and no dismissal ([PopScope] blocks Escape/back and
/// the barrier is non-dismissible): the update gate pops it on download
/// failure, and on success the app quits with it still up. Indeterminate
/// because `updat` downloads with a single `http.get` — no progress stream.
class UpdateDownloadDialog extends StatelessWidget {
  const UpdateDownloadDialog({super.key});

  /// Shows the dialog; the returned future completes when the update gate
  /// pops it (download failure) — on success the app exits first.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDownloadDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return PopScope(
      canPop: false,
      child: ResponsiveDialogScaffold(
        title: const Text('DOWNLOADING UPDATE…'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(width: layout.tabSpacing),
            Flexible(
              child: Text(
                'Getman will close and run the installer when the download '
                'finishes.',
                style: TextStyle(fontSize: layout.fontSizeNormal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

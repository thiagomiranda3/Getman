// Update-available dialog (SKIP THIS VERSION / LATER / UPDATE NOW); see class
// doc below. UPDATE NOW hands the download off to the browser, never
// downloads in-process.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:provider/provider.dart';

/// Themed dialog shown when an update is available. Shows the version line,
/// optional changelog, a note about how the download works, and three actions:
/// SKIP THIS VERSION, LATER, and UPDATE NOW. UPDATE NOW opens the release
/// download in the user's browser (see `update_gate_io._openDownloadInBrowser`)
/// and closes the dialog.
///
/// Normally opened via [UpdateDialog.show], which injects [UpdateController]
/// via [ChangeNotifierProvider] and [SettingsBloc] via [BlocProvider]. The
/// widget tolerates a missing [UpdateController] in the tree (render-only
/// tests): controller callbacks become no-ops.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    required this.latestVersion,
    required this.currentVersion,
    required this.changelog,
    super.key,
  });

  final String latestVersion;
  final String currentVersion;
  final String? changelog;

  /// Opens the dialog, injecting [controller] + [settingsBloc] into the tree.
  static Future<void> show(
    BuildContext context, {
    required String latestVersion,
    required String currentVersion,
    required String? changelog,
    required UpdateController controller,
    required SettingsBloc settingsBloc,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider<UpdateController>.value(
        value: controller,
        child: BlocProvider.value(
          value: settingsBloc,
          child: UpdateDialog(
            latestVersion: latestVersion,
            currentVersion: currentVersion,
            changelog: changelog,
          ),
        ),
      ),
    );
  }

  /// Returns the [UpdateController] from the widget tree, or `null` if not
  /// present (e.g. in render-only tests).
  UpdateController? _controller(BuildContext context) {
    try {
      return context.read<UpdateController>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final controller = _controller(context);

    return ResponsiveDialogScaffold(
      title: const Text('UPDATE AVAILABLE'),
      content: _DialogBody(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        changelog: changelog,
        layout: layout,
      ),
      actions: [
        TextButton(
          key: const ValueKey('update_skip_button'),
          onPressed: () {
            context.read<SettingsBloc>().add(
              SetSkippedUpdateVersion(latestVersion),
            );
            Navigator.pop(context);
          },
          child: const Text('SKIP THIS VERSION'),
        ),
        TextButton(
          key: const ValueKey('update_later_button'),
          onPressed: () {
            controller?.dismiss?.call();
            Navigator.pop(context);
          },
          child: const Text('LATER'),
        ),
        TextButton(
          key: const ValueKey('update_now_button'),
          onPressed: () {
            unawaited(controller?.startUpdate?.call());
            Navigator.pop(context);
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
          child: const Text('UPDATE NOW'),
        ),
      ],
    );
  }
}

/// Stateless body content for [UpdateDialog].
class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.latestVersion,
    required this.currentVersion,
    required this.changelog,
    required this.layout,
  });

  final String latestVersion;
  final String currentVersion;
  final String? changelog;
  final AppLayout layout;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Getman $latestVersion is available (you have $currentVersion).',
          style: TextStyle(fontSize: layout.fontSizeNormal),
        ),
        SizedBox(height: layout.tabSpacing),
        if (changelog != null && changelog!.trim().isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Text(
                changelog!,
                style: TextStyle(fontSize: layout.fontSizeSmall),
              ),
            ),
          ),
        SizedBox(height: layout.tabSpacing),
        Text(
          'UPDATE NOW opens the download in your browser. Getman is not '
          'code-signed, so your OS may warn on first launch — allow it via '
          'right-click → Open (macOS) or More info → Run anyway (Windows).',
          style: TextStyle(fontSize: layout.fontSizeSmall),
        ),
      ],
    );
  }
}

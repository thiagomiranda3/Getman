// Readable script API reference: bounded desktop width, scrollable sections,
// and shared responsive dialog chrome for small windows and every theme.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

class ScriptHelpDialog extends StatelessWidget {
  const ScriptHelpDialog({super.key});

  static Future<void> show(BuildContext context) => showResponsiveDialog<void>(
    context,
    builder: (_) => const ScriptHelpDialog(),
  );

  static const _sections = [
    (
      'WHEN SCRIPTS RUN',
      'Use gm for request, response, variables, JWT and tests. '
          'Scripts run only when sending HTTP requests. '
          'No Node, npm, fetch or pm.* compatibility.',
    ),
    (
      'VARIABLES',
      'gm.variables.get/set: execution-local values.\n\n'
          'gm.environment.get/set/unset: persisted changes are applied '
          'only after successful completion.\n\n'
          'Collection variables are read-only.',
    ),
    (
      'REQUEST & RESPONSE',
      'PRE-REQUEST: use gm.request.headers.set and gm.request.setBody '
          'before HTTP.\n\n'
          'POST-RESPONSE: use gm.response.json/header/lookup after HTTP.',
    ),
    (
      'JWT & TESTS',
      'gm.jwt.decode reads JWT payloads without signature verification.\n\n'
          'gm.test works in both stages.',
    ),
    (
      'LIMITS PER STAGE',
      'Execution: 1 second · Heap: 32 MiB\n'
          'Source: 256 KiB · Input: 8 MiB · Output: 1 MiB\n'
          'Tests: 200 · Console: 200 entries / 64 KiB',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ResponsiveDialogScaffold(
      title: const Text('SCRIPT HELP'),
      content: SizedBox(
        width: layout.settingsDialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (title, body) in _sections)
                Padding(
                  padding: EdgeInsets.only(bottom: layout.pagePadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: context.appTypography.titleWeight,
                        ),
                      ),
                      SizedBox(height: layout.tabSpacing),
                      SelectableText(body),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}

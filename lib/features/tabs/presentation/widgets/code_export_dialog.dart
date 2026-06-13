import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/code_gen_service.dart';

/// "Generate code" dialog: pick a target language and copy a request snippet.
/// The snippet keeps `{{env vars}}` verbatim (it's a template).
class CodeExportDialog extends StatefulWidget {
  final HttpRequestConfigEntity config;
  const CodeExportDialog({super.key, required this.config});

  static Future<void> show(BuildContext context, HttpRequestConfigEntity config) {
    return showResponsiveDialog(
      context,
      builder: (_) => CodeExportDialog(config: config),
    );
  }

  @override
  State<CodeExportDialog> createState() => _CodeExportDialogState();
}

class _CodeExportDialogState extends State<CodeExportDialog> {
  CodeGenTarget _target = CodeGenTarget.curl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final code = CodeGenService.generate(widget.config, _target);

    return ResponsiveDialogScaffold(
      title: const Text('GENERATE CODE'),
      content: SizedBox(
        width: context.isDialogFullscreen ? double.maxFinite : 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<CodeGenTarget>(
              value: _target,
              isExpanded: true,
              items: [
                for (final t in CodeGenTarget.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (next) {
                if (next != null) setState(() => _target = next);
              },
            ),
            SizedBox(height: layout.sectionSpacing),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(layout.pagePadding),
                decoration: BoxDecoration(
                  color: context.appPalette.codeBackground,
                  border: Border.all(color: theme.dividerColor, width: layout.borderThin),
                  borderRadius: BorderRadius.circular(context.appShape.panelRadius),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    code,
                    style: TextStyle(
                      fontFamily: context.appTypography.codeFontFamily,
                      fontSize: layout.fontSizeCode,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            showAppSnackBar(
              context,
              'Code copied to clipboard',
              backgroundColor: theme.colorScheme.secondary,
            );
          },
          child: Text('COPY',
              style: TextStyle(fontWeight: context.appTypography.titleWeight)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('CLOSE',
              style: TextStyle(fontWeight: context.appTypography.titleWeight)),
        ),
      ],
    );
  }
}

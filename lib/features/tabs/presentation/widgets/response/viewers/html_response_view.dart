import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/html_open_external.dart';

/// Shows an HTML response as selectable source plus an "OPEN IN BROWSER"
/// action that writes the bytes to a temp file and launches the real browser.
/// No embedded webview — source stays fully inspectable.
class HtmlResponseView extends StatelessWidget {
  const HtmlResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  Future<void> _openInBrowser(BuildContext context) async {
    try {
      await openHtmlInBrowser(bytes);
    } on Object catch (e) {
      if (context.mounted) showAppSnackBar(context, 'Could not open: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(layout.tabSpacing),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              key: const ValueKey('html_open_in_browser'),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('OPEN IN BROWSER'),
              onPressed: () => _openInBrowser(context),
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: context.appPalette.codeBackground,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(layout.pagePadding),
              child: SelectableText(
                utf8.decode(bytes, allowMalformed: true),
                style: TextStyle(
                  fontFamily: typography.codeFontFamily,
                  fontSize: layout.fontSizeCode,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

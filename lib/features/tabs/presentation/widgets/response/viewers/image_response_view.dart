// PREVIEW viewer for an image response: Image.memory in an InteractiveViewer
// (pan/zoom), falling back to a short note on decode failure.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Renders an image response from raw bytes, pannable/zoomable on a themed
/// surface. Falls back to a short note if the bytes don't decode.
class ImageResponseView extends StatelessWidget {
  const ImageResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ColoredBox(
      color: context.appPalette.codeBackground,
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: InteractiveViewer(
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => Text(
                'Cannot decode image',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

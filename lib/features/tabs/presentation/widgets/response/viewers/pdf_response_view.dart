import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:pdfx/pdfx.dart';

/// Renders a PDF response inline via pdfx (native pdfium).
///
/// Shows a loading indicator while the document is parsed, falls back to
/// a short "Cannot render PDF" note on any load error (e.g. corrupt bytes
/// or missing native plugin in the test VM), and disposes the controller
/// properly on unmount.
class PdfResponseView extends StatefulWidget {
  const PdfResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  @override
  State<PdfResponseView> createState() => _PdfResponseViewState();
}

class _PdfResponseViewState extends State<PdfResponseView> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.bytes),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.appPalette.codeBackground,
      child: PdfViewPinch(
        controller: _controller,
        onDocumentError: (_) {},
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) => Center(
            child: Text('Cannot render PDF: $error'),
          ),
        ),
      ),
    );
  }
}

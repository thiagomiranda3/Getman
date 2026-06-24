import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:pdfx/pdfx.dart';

/// Renders a PDF response inline via pdfx (native pdfium).
///
/// Manages the document load explicitly so a corrupt/truncated PDF always
/// shows the "Cannot render PDF" fallback — never an infinite spinner —
/// regardless of whether pdfx's internal state machine auto-transitions.
class PdfResponseView extends StatefulWidget {
  const PdfResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  @override
  State<PdfResponseView> createState() => _PdfResponseViewState();
}

class _PdfResponseViewState extends State<PdfResponseView> {
  PdfControllerPinch? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDocument());
  }

  Future<void> _loadDocument() async {
    try {
      final doc = await PdfDocument.openData(widget.bytes);
      if (!mounted) {
        await doc.close();
        return;
      }
      setState(
        () => _controller = PdfControllerPinch(document: Future.value(doc)),
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: context.appPalette.codeBackground,
        child: Center(
          child: Text(
            'Cannot render PDF',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      );
    }

    if (_controller == null) {
      return ColoredBox(
        color: context.appPalette.codeBackground,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ColoredBox(
      color: context.appPalette.codeBackground,
      child: PdfViewPinch(
        controller: _controller!,
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) => Center(
            child: Text(
              'Cannot render PDF: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

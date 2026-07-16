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

  @override
  void didUpdateWidget(PdfResponseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A re-send reuses this element (the panel keys viewers by kind, not by
    // response) — without a reload the previous PDF stays on screen.
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _controller?.dispose();
      setState(() {
        _controller = null;
        _error = null;
      });
      unawaited(_loadDocument());
    }
  }

  Future<void> _loadDocument() async {
    // Guards a stale load finishing after a newer response replaced it.
    final bytes = widget.bytes;
    try {
      // pdfx's PdfDocument.openData calls assertHasPdfSupport() WITHOUT
      // awaiting it, so on a platform with no pdfium binding (e.g. the headless
      // test VM / CI) that assert throws a *detached* async error no try/catch
      // here can catch. Pre-check support (awaited) and fall back instead of
      // ever invoking openData on an unsupported platform.
      if (!await hasPdfSupport()) {
        if (mounted) setState(() => _error = PlatformNotSupportedException());
        return;
      }
      final doc = await PdfDocument.openData(bytes);
      if (!mounted || !identical(bytes, widget.bytes)) {
        await doc.close();
        return;
      }
      setState(
        () => _controller = PdfControllerPinch(document: Future.value(doc)),
      );
    } on Object catch (e) {
      if (mounted && identical(bytes, widget.bytes)) {
        setState(() => _error = e);
      }
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

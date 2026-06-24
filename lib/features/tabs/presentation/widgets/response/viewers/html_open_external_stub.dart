import 'dart:typed_data';

/// Web (and any non-dart:io) build: opening in an external browser via a temp
/// file is unavailable. The real implementation lives in
/// `html_open_external_io.dart`.
Future<void> openHtmlInBrowser(Uint8List bytes) async {}

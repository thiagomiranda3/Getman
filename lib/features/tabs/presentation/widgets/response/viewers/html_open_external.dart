// Conditional export for openHtmlInBrowser: resolves to the real dart:io
// implementation on native platforms and to a no-op stub on web (where
// dart:io / path_provider are unavailable). Keeps HtmlResponseView web-safe.
export 'html_open_external_stub.dart'
    if (dart.library.io) 'html_open_external_io.dart';

// defaultUserAgent(): the User-Agent dart:io's HttpClient sends when no
// explicit header is set — "Dart/<major.minor> (dart:io)" — so the HEADERS
// tab's auto-generated list shows the real value. dart:io on native (reads
// Platform.version exactly like dart:io's own _getHttpVersion), null on web
// (the browser owns the header). Resolved via a conditional import so
// `dart:io` never leaks into the web build.
export 'default_user_agent_stub.dart'
    if (dart.library.io) 'default_user_agent_io.dart';

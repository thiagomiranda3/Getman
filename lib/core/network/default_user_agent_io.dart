// dart:io implementation of default_user_agent.dart: rebuilds the string
// dart:io's HttpClient sends by default ("Dart/<major.minor> (dart:io)") from
// Platform.version, mirroring the SDK's own _getHttpVersion().
import 'dart:io';

/// The User-Agent dart:io sends when the request carries none.
String? defaultUserAgent() {
  final version = Platform.version;
  final firstDot = version.indexOf('.');
  final secondDot = version.indexOf('.', firstDot + 1);
  final majorMinor = secondDot > 0 ? version.substring(0, secondDot) : version;
  return 'Dart/$majorMinor (dart:io)';
}

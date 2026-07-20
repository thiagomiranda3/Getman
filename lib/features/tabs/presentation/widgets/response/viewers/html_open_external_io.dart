// Native (dart:io) half of the "OPEN IN BROWSER" action for HTML responses:
// writes the bytes to a temp file and launches it via url_launcher. Routed to
// only on non-web platforms — see html_open_external.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Writes [bytes] to a temp `.html` file and opens it in the system browser.
/// Native (dart:io) implementation — see `html_open_external.dart` for routing.
Future<void> openHtmlInBrowser(Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/getman_response_${DateTime.now().millisecondsSinceEpoch}.html',
  );
  await file.writeAsBytes(bytes);
  await launchUrl(file.uri);
}

// Opens a URL in the system browser via url_launcher; returns false instead
// of throwing on a malformed URL or missing handler.

import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser. Returns false (never throws) when the
/// url is malformed or no handler is available — callers show a snackbar.
Future<bool> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Rich response visualizers (DL1): a response whose content-type is CSV /
/// HTML / an image routes to its dedicated PREVIEW viewer instead of the text
/// body. Body bytes are captured **live** (not persisted), so a real send is
/// required. Exercises the content-type → viewer routing + the PREVIEW/RAW
/// toggle end to end.
///
/// Only the pure-Flutter viewers (CSV / HTML / image) are driven here. Video /
/// audio (media_kit) and PDF (pdfx) lean on native players that don't render
/// reliably under headless integration_test; those keep their widget-level
/// tests and a manual native-playback check.

// A 1x1 transparent PNG — small + valid, so Image.memory decodes and renders.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// A [MockResponder] that returns [body] with an explicit [contentType], so the
/// app classifies the response as media and captures its bytes.
MockResponder _bytesResponder(String contentType, List<int> body) {
  return (HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, contentType)
      ..add(body);
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('a CSV response renders the table viewer + RAW toggle', (
    $,
  ) async {
    final server = await MockServer.start(
      responder: _bytesResponder(
        'text/csv',
        utf8.encode('name,age\nAda,36\nBob,40'),
      ),
    );
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/data.csv'));

    // The CSV table viewer mounts instead of the text body.
    await $(const ValueKey('media_preview_csv')).waitUntilVisible();

    // The PREVIEW/RAW toggle switches to the binary card without crashing.
    await $(
      const ValueKey('media_toggle_RAW'),
    ).tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);
    await $(
      const ValueKey('media_toggle_PREVIEW'),
    ).tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);
    await $(const ValueKey('media_preview_csv')).waitUntilVisible();
  });

  patrolWidgetTest('an HTML response renders the HTML viewer', ($) async {
    final server = await MockServer.start(
      responder: _bytesResponder(
        'text/html',
        utf8.encode('<html><body><h1>Hello</h1></body></html>'),
      ),
    );
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/page.html'));
    await $(const ValueKey('media_preview_html')).waitUntilVisible();
  });

  patrolWidgetTest('an image response renders the image viewer', ($) async {
    final server = await MockServer.start(
      responder: _bytesResponder('image/png', _pngBytes),
    );
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/pixel.png'));
    await $(const ValueKey('media_preview_image')).waitUntilVisible();
  });
}

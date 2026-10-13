import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/widgets/response/large_response_text_view.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest(
    '11.3 MB JSON supports prettify, dense search and navigation',
    (
      $,
    ) async {
      // Long unbroken fields exercise the worst-case paragraph layout. This
      // server is local and contains no production account data or credentials.
      final body = '{"description":"${'x' * 11300000}","total":42}';
      final server = await MockServer.start(
        responder: (request) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(body);
        },
      );
      addTearDown(server.close);
      await bootGetman($);
      await sendTo($, server.url('/large-json'));
      await waitForStatus($, 200);
      await $('PRETTIFY ANYWAY').tap();
      await $(find.textContaining('— FORMATTED')).waitUntilVisible();
      final formatted = $.tester
          .widget<LargeResponseTextView>(
            find.byType(LargeResponseTextView),
          )
          .text;
      expect(formatted.substring(0, 24), startsWith('{\n    "description":'));
      expect(
        formatted.substring(formatted.length - 20),
        endsWith('"total": 42\n}'),
      );

      await $(const ValueKey('response_find_button')).tap();
      await $(const ValueKey('large_find_field')).enterText('x');
      await $('1/11300000').waitUntilVisible();
      await $(const ValueKey('large_find_next')).tap();
      expect($('2/11300000'), findsOneWidget);
      await $(const ValueKey('large_find_prev')).tap();
      expect($('1/11300000'), findsOneWidget);
      await $(const ValueKey('large_find_field')).enterText('"total"');
      await $('1/1').waitUntilVisible();
      final snippet = $.tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('large_find_window_text')),
          )
          .textSpan!
          .toPlainText();
      expect(snippet, contains('"total": 42'));
      expect(snippet.length, lessThan(4200));
      await $(const ValueKey('large_find_close')).tap();
      await openResponseTab($, 'HEADERS');
      await openResponseTab($, 'BODY');
      expect(find.byType(LargeResponseTextView), findsOneWidget);
      expect($.tester.takeException(), isNull);
    },
  );
}

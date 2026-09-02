// Unit test for defaultUserAgent(): the User-Agent dart:io sends when no
// explicit header is set — "Dart/<major.minor> (dart:io)" — surfaced so the
// HEADERS tab's auto-generated list can show the real value.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/default_user_agent.dart';

void main() {
  test(
    'defaultUserAgent mirrors dart:io\'s "Dart/<major.minor> (dart:io)"',
    () {
      expect(
        defaultUserAgent(),
        matches(RegExp(r'^Dart/\d+\.\d+ \(dart:io\)$')),
      );
    },
  );
}

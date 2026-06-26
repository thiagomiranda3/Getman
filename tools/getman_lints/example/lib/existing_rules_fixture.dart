// Fixtures for getman_lints. Imports are intentionally unresolved — every rule
// matches on file path + raw import URI + syntax, never on resolved elements,
// so these files need no real dependencies. The analyzer's own
// "uri_does_not_exist" is not a custom_lint lint and does not affect expect_lint.
// ignore_for_file: uri_does_not_exist, unused_import, unused_local_variable

import 'package:flutter/material.dart';

void brandColorIsFlagged() {
  // expect_lint: avoid_hardcoded_brand_colors
  final c = Colors.red;
}

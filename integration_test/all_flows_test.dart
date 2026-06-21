import 'package:integration_test/integration_test.dart';

import 'flows/auth_deep_test.dart' as auth_deep;
import 'flows/auth_test.dart' as auth;
import 'flows/body_types_test.dart' as body_types;
import 'flows/chaining_deep_test.dart' as chaining_deep;
import 'flows/chaining_rules_test.dart' as chaining_rules;
import 'flows/code_export_edits_test.dart' as code_export_edits;
import 'flows/code_gen_test.dart' as code_gen;
import 'flows/collections_deep_test.dart' as collections_deep;
import 'flows/collections_test.dart' as collections;
import 'flows/command_palette_deep_test.dart' as command_palette_deep;
import 'flows/command_palette_test.dart' as command_palette;
import 'flows/cookies_test.dart' as cookies;
import 'flows/environments_deep_test.dart' as environments_deep;
import 'flows/environments_test.dart' as environments;
import 'flows/error_states_test.dart' as error_states;
import 'flows/extras_test.dart' as extras;
import 'flows/history_deep_test.dart' as history_deep;
import 'flows/history_test.dart' as history;
import 'flows/json_fold_test.dart' as json_fold;
import 'flows/panels_test.dart' as panels;
import 'flows/realtime_deep_test.dart' as realtime_deep;
import 'flows/realtime_sse_test.dart' as realtime_sse;
import 'flows/realtime_ws_test.dart' as realtime_ws;
import 'flows/request_config_deep_test.dart' as request_config_deep;
import 'flows/request_config_test.dart' as request_config;
import 'flows/request_send_test.dart' as request_send;
import 'flows/response_views_deep_test.dart' as response_views_deep;
import 'flows/response_views_test.dart' as response_views;
import 'flows/responsive_test.dart' as responsive;
import 'flows/saved_examples_test.dart' as saved_examples;
import 'flows/settings_network_test.dart' as settings_network;
import 'flows/settings_tabs_test.dart' as settings_tabs;
import 'flows/settings_test.dart' as settings;
import 'flows/smoke_test.dart' as smoke;
import 'flows/tab_management_test.dart' as tab_management;
import 'flows/tab_shortcuts_test.dart' as tab_shortcuts;
import 'flows/tabs_test.dart' as tabs;
import 'flows/theme_motion_send_test.dart' as theme_motion_send;
import 'flows/theme_stress_test.dart' as theme_stress;
import 'flows/variable_substitution_test.dart' as variable_substitution;

/// Aggregator: runs every flow in a **single** `flutter test` invocation, so
/// the macOS app is built and launched **once** and all cases run sequentially
/// in that one process (instead of rebuilding per file).
///
/// This is the entry point `run_macos.sh` uses. Each imported flow still has
/// its own `main()`, so you can also run a single flow on its own during
/// development (`fvm flutter test integration_test/flows/<name>_test.dart`).
///
/// To add a flow: create `flows/<name>_test.dart`, then import it here and call
/// its `main()` below.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Core round-trip + rendering.
  smoke.main();
  request_send.main();
  json_fold.main();
  variable_substitution.main();

  // Feature flows.
  tabs.main();
  tab_management.main();
  tab_shortcuts.main();
  panels.main();
  request_config.main();
  request_config_deep.main();
  body_types.main();
  history.main();
  history_deep.main();
  collections.main();
  collections_deep.main();
  saved_examples.main();
  environments.main();
  environments_deep.main();
  chaining_rules.main();
  chaining_deep.main();
  error_states.main();
  cookies.main();
  realtime_ws.main();
  realtime_sse.main();
  realtime_deep.main();
  auth.main();
  auth_deep.main();
  code_gen.main();
  code_export_edits.main();
  settings.main();
  settings_network.main();
  settings_tabs.main();
  response_views.main();
  response_views_deep.main();
  responsive.main();
  theme_stress.main();
  theme_motion_send.main();
  command_palette.main();
  command_palette_deep.main();
  extras.main();
}

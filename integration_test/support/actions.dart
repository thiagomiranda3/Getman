import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' show Finder, find;
import 'package:patrol_finders/patrol_finders.dart';

/// Reusable interactions for driving Getman in E2E flows. These wrap the stable
/// finders (keys / verbatim labels) so individual flow tests read like a script
/// and survive UI tweaks in one place.
///
/// **Slow-motion / watch mode:** pass `--dart-define=E2E_SLOW_MS=<ms>` (or use
/// `E2E_SLOW_MS=<ms> bash integration_test/run_macos.sh [flow]`) to insert a
/// real-time pause after each scripted step, so you can watch the macOS app
/// window change state as the flow runs. Defaults to 0 (no pause) so normal /
/// CI runs stay fast. The pause is woven into the helpers below; raw
/// `$(...).tap()` calls inside individual flows don't pause.
/// Slow-motion pause in milliseconds, from `--dart-define=E2E_SLOW_MS=<ms>`.
/// A getter (not a top-level const) so the analyzer doesn't const-fold the
/// default 0 into the [Duration] below and flag it const / redundant — the real
/// value arrives via `--dart-define` at run time.
int get e2eSlowMs => const int.fromEnvironment('E2E_SLOW_MS');

/// Holds the current frame on screen for [e2eSlowMs] of real wall-clock time
/// (integration_test runs on a live binding, so `pump(duration)` actually
/// waits), giving a human a beat to see the step that just happened. No-op when
/// slow mode is off.
Future<void> slowMo(PatrolTester $) async {
  final ms = e2eSlowMs;
  if (ms <= 0) return;
  await $.tester.pump(Duration(milliseconds: ms));
}

/// Types [url] into the active tab's URL field, replacing whatever was there
/// (e.g. the first-run seed URL). Scoped to the on-screen field: inactive tabs
/// keep their own (Offstage, non-hit-testable) `url_field` in the tree.
Future<void> enterUrl(PatrolTester $, String url) async {
  await $(find.byKey(const ValueKey('url_field')).hitTestable()).enterText(url);
  await slowMo($);
}

/// Reads the URL text of the currently-active tab (the only on-screen,
/// hit-testable `url_field`).
String activeUrl(PatrolTester $) {
  final field = $.tester.widget<EditableText>(
    find
        .descendant(
          of: find.byKey(const ValueKey('url_field')).hitTestable(),
          matching: find.byType(EditableText),
        )
        .hitTestable(),
  );
  return field.controller.text;
}

/// Taps SEND **without settling** — the response-pending view shows a
/// continuously-animating shimmer, so settling here would never complete. The
/// caller must wait for the response (e.g. `await waitForStatus($, 200)`).
Future<void> tapSend(PatrolTester $) async {
  await $(
    find.byKey(const ValueKey('send')).hitTestable(),
  ).tap(settlePolicy: SettlePolicy.noSettle);
  await slowMo($);
}

/// Enters [url] and taps SEND. Does not wait for the response — follow with
/// [waitForStatus].
Future<void> sendTo(PatrolTester $, String url) async {
  await enterUrl($, url);
  await tapSend($);
}

/// Pumps frames (without requiring a settle, so the shimmer can't block it)
/// until the response STATUS chip shows [statusCode].
Future<void> waitForStatus(PatrolTester $, int statusCode) async {
  await $('$statusCode').waitUntilVisible();
  await slowMo($);
}

// ---------------------------------------------------------------------------
// Tab management
// ---------------------------------------------------------------------------

/// Opens a fresh request tab via the "+" button.
Future<void> newTab(PatrolTester $) async {
  await $(const ValueKey('add_tab_button')).tap();
  await slowMo($);
}

// ---------------------------------------------------------------------------
// Request configuration
// ---------------------------------------------------------------------------

/// Selects an HTTP [method] (e.g. `POST`) from the method dropdown.
Future<void> setMethod(PatrolTester $, String method) async {
  await $(const ValueKey('method_selector')).tap();
  await $(method).tap();
  await slowMo($);
}

/// Selects a request [kind] label — `HTTP`, `WS`, or `SSE`.
Future<void> setRequestKind(PatrolTester $, String kind) async {
  await $(const ValueKey('request_kind_selector')).tap();
  await $(kind).tap();
  await slowMo($);
}

/// Taps a request-config sub-tab by its [label] (`PARAMS`/`AUTH`/`HEADERS`/
/// `BODY`/`RULES`).
Future<void> openRequestTab(PatrolTester $, String label) async {
  await $(ValueKey('reqtab_tab_$label')).tap();
  await slowMo($);
}

/// Taps a response sub-tab by its [label] (`BODY`/`HEADERS`/`COOKIES`/`TESTS`).
Future<void> openResponseTab(PatrolTester $, String label) async {
  await $(ValueKey('resptab_tab_$label')).tap();
  await slowMo($);
}

/// Taps a side-menu tab by its [label] (`COLLECTIONS`/`HISTORY`).
Future<void> openSideMenuTab(PatrolTester $, String label) async {
  await $(ValueKey('menutab_tab_$label')).tap();
  await slowMo($);
}

/// Enters a query-param key/value into the params editor row [index].
/// Assumes the PARAMS tab is open.
Future<void> setParam(
  PatrolTester $,
  int index,
  String key,
  String value,
) async {
  await $(ValueKey('param_key_$index')).enterText(key);
  await $(ValueKey('param_val_$index')).enterText(value);
  await slowMo($);
}

/// Enters a header key/value into the headers editor row [index].
/// Assumes the HEADERS tab is open.
Future<void> setHeader(
  PatrolTester $,
  int index,
  String key,
  String value,
) async {
  await $(ValueKey('header_key_$index')).enterText(key);
  await $(ValueKey('header_val_$index')).enterText(value);
  await slowMo($);
}

/// Selects a body type by its chip label (`NONE`/`RAW`/`FORM`/`MULTIPART`/
/// `BINARY`). Assumes the BODY tab is open.
Future<void> setBodyType(PatrolTester $, String label) async {
  await $(ValueKey('bodytype_$label')).tap();
  await slowMo($);
}

// ---------------------------------------------------------------------------
// Dialogs / chrome
// ---------------------------------------------------------------------------

/// Types [text] into the shared single-line name-prompt dialog field.
Future<void> enterPromptText(PatrolTester $, String text) async {
  await $(const ValueKey('name_prompt_field')).enterText(text);
  await slowMo($);
}

/// Pumps a bounded number of real-time frames WITHOUT requiring a settle. Safe
/// under themes that animate forever (RPG starfield, glass shimmer) where
/// `pumpAndSettle` never returns. Use after a `noSettle` tap to let a dialog /
/// menu / theme transition land.
Future<void> pumpFrames(
  PatrolTester $, {
  int frames = 12,
  int ms = 40,
}) async {
  for (var i = 0; i < frames; i++) {
    await $.tester.pump(Duration(milliseconds: ms));
  }
}

/// Opens the Settings dialog from the side-menu header. Animation-safe (the
/// active theme may animate continuously, so we can't `pumpAndSettle`).
Future<void> openSettings(PatrolTester $) async {
  await $(
    const ValueKey('settings_button'),
  ).tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await slowMo($);
}

/// Taps a Settings dialog tab by its [label]
/// (`GENERAL`/`APPEARANCE`/`NETWORK`/`WORKSPACE`). Assumes Settings is open.
/// Animation-safe (themes may animate forever, so no `pumpAndSettle`).
Future<void> openSettingsTab(PatrolTester $, String label) async {
  await $(
    ValueKey('settingstab_tab_$label'),
  ).tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await slowMo($);
}

/// Opens the active-environment selector popup menu.
Future<void> openEnvironmentSelector(PatrolTester $) async {
  await $(const ValueKey('environment_selector')).tap();
  await slowMo($);
}

// ---------------------------------------------------------------------------
// Tab strip helpers (identity-agnostic — tabs are keyed by dynamic uuid)
// ---------------------------------------------------------------------------

/// Finder for every open request tab's root widget (keyed `tab_<id>`), in
/// strip order. Excludes the per-tab close button (`tab_close_<id>`) and the
/// hover tooltip card (`tab_tooltip_<id>`).
Finder allTabs() => find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> &&
      k.value.startsWith('tab_') &&
      !k.value.startsWith('tab_close_') &&
      !k.value.startsWith('tab_tooltip_');
});

/// Number of open request tabs (counts per-tab close buttons, one per tab).
int tabCount(PatrolTester $) {
  final finder = find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('tab_close_');
  });
  return $.tester.widgetList(finder).length;
}

/// Right-clicks (secondary tap) the tab at [index] to open its context menu
/// (CLOSE / CLOSE OTHERS / CLOSE TO THE RIGHT / DUPLICATE / COPY URL).
Future<void> openTabMenu(PatrolTester $, int index) async {
  await $.tester.tap(allTabs().at(index), buttons: kSecondaryButton);
  await $.pumpAndSettle();
  await slowMo($);
}

// ---------------------------------------------------------------------------
// Keyboard shortcuts
// ---------------------------------------------------------------------------

/// Sends a keyboard shortcut with optional modifiers (macOS key events). Pass
/// `settle: false` for combos that kick off a never-settling animation (e.g.
/// Cmd+Enter starts the response shimmer) — then wait via [waitForStatus].
Future<void> sendShortcut(
  PatrolTester $,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
  bool shift = false,
  bool settle = true,
}) async {
  final mods = <LogicalKeyboardKey>[
    if (meta) LogicalKeyboardKey.metaLeft,
    if (control) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final m in mods) {
    await $.tester.sendKeyDownEvent(m, platform: 'macos');
  }
  await $.tester.sendKeyEvent(key, platform: 'macos');
  for (final m in mods.reversed) {
    await $.tester.sendKeyUpEvent(m, platform: 'macos');
  }
  if (settle) {
    await $.pumpAndSettle();
  } else {
    await $.tester.pump();
  }
  await slowMo($);
}

// ---------------------------------------------------------------------------
// Settings / theming
// ---------------------------------------------------------------------------

/// Opens Settings, selects the theme whose dropdown label is [displayName]
/// (e.g. `EDITORIAL`, `LIQUID GLASS`), then closes the dialog. Animation-safe:
/// uses `noSettle` taps + bounded pumps because RPG/glass animate forever.
/// Never pass the currently-active theme — the open dropdown shows it twice
/// (button label + menu item), making the finder ambiguous.
Future<void> setTheme(PatrolTester $, String displayName) async {
  await openSettings($);
  await openSettingsTab($, 'APPEARANCE');
  await $(
    const ValueKey('theme_dropdown'),
  ).tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await $(displayName).tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await slowMo($);
}

/// Opens Settings, taps the row whose label is [label] (e.g. `DARK MODE`,
/// `COMPACT MODE`, `REDUCE VISUAL EFFECTS`), then closes the dialog.
/// Animation-safe (see [setTheme]).
Future<void> toggleSettingRow(PatrolTester $, String label) async {
  await openSettings($);
  await openSettingsTab($, 'APPEARANCE');
  await $(label).tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
  await pumpFrames($);
  await slowMo($);
}

/// Opens the side-menu drawer (drawer-nav layouts ≤ 900 px wide) via the menu
/// button in the tab bar.
Future<void> openDrawer(PatrolTester $) async {
  await $(find.byIcon(Icons.menu)).tap();
  await $.pumpAndSettle();
  await slowMo($);
}

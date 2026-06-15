# End-to-end tests (macOS)

These drive the **real Getman app** in a real macOS window — launch it, click,
type, send requests, and assert on what the user would see — so you don't have
to manually click through features before publishing.

## What this is built on

- **`patrol_finders`** — the `$` finder API (`$('text')`, `$(Key(...))`,
  `.tap()`, `.enterText()`, `.waitUntilVisible()`).
- **Flutter `integration_test`** — runs the compiled app on a real device.

> We use `patrol_finders` rather than the full `patrol` native harness because
> Patrol's **native automation does not support macOS desktop** (it's alpha, no
> native support). The finder API is all we need on desktop and runs under
> `integration_test` with no native test target. (If you ever need to automate
> native OS dialogs — file pickers, permissions — run the flows on a mobile
> simulator instead, where patrol native works.)

## Running

Run the whole suite — **builds + launches the app once**, then runs every case:

```bash
bash integration_test/run_macos.sh
```

This runs `all_flows_test.dart`, an aggregator that composes every flow into a
single entry point. One build (~12-15s), then each case takes ~1s.

Run a single flow while developing it (rebuilds, but isolates one flow):

```bash
fvm flutter test integration_test/flows/request_send_test.dart -d macos
```

Toolchain sanity check (no app, just proves the pipeline builds/runs):

```bash
fvm flutter test integration_test/pipeline_smoke_test.dart -d macos
```

## Watch it run (see the real app)

On macOS the test **renders to a real, visible app window** — you watch the
taps/typing happen. `bootGetman` resizes that real window to a desktop size at
native scale (see Isolation above); it does **not** override
`tester.view.physicalSize`, which would decouple rendering from the window and
strand it on the "Test starting…" stub. So watching just needs a **single flow**
(followable) plus **slow-motion**:

```bash
bash integration_test/run_macos_watch.sh tabs            # one flow, slow, visible
bash integration_test/run_macos_watch.sh chaining_rules
E2E_SLOW_MS=1200 bash integration_test/run_macos_watch.sh environments
```

`run_macos_watch.sh` is a thin wrapper over `run_macos.sh` that turns
slow-motion on by default (700 ms/step). Equivalently:

```bash
E2E_SLOW_MS=700 bash integration_test/run_macos.sh tabs
```

The pause (`slowMo` in `support/actions.dart`, gated on the `E2E_SLOW_MS`
dart-define) fires after each scripted **helper** step; raw `$(...).tap()` calls
inside a flow don't pause. In watch mode the live binding is also set to
`fullyLive` so animations render continuously.

> Not a Cypress GUI: there's no command-log / time-travel / click-to-step —
> Flutter's `integration_test` has no equivalent. What you get is a live,
> slow-able run of the real app window.

**Why an aggregator and not `flutter test integration_test -d macos`?** The
Flutter *desktop* runner can only host one integration_test **file** per
`flutter test` call — passing several together makes the next one fail with
"Error waiting for a debug connection." A single aggregator *file* that imports
the others sidesteps that: it's one file (one build/launch), and all the cases
it pulls in run sequentially in that one app process.

## Isolation (your real data is safe)

Each flow boots the app against a **throwaway temp Hive profile** (via
`di.init(storageDirectoryOverride: ...)`), so a run never reads or wipes your
real saved collections / history / settings. Cleanup (close boxes, reset DI,
delete the temp dir) is registered with `addTearDown`, so it runs even when a
test fails.

The flows target the **desktop layout** (inline side menu + split request/
response panes — `reqtab_*` / `resptab_*` / `menutab_*` anchors). `flutter test`
boots the macOS app at an 800×600 surface (tablet → drawer side menu), so
`bootGetman` resizes the **real window** to `kE2eWindowSize` (1500×950) at
native scale via a test-only platform channel (`getman/test_window`, handled in
`macos/Runner/MainFlutterWindow.swift`). It's an actual resize — the app lays
out at the new size at the native pixel ratio — so responsive breakpoints fire
for real (call `resizeWindow($, size)` mid-flow to exercise them) and the window
stays visible. (We do **not** fake the size via `devicePixelRatio`; that scales
the pixels instead of resizing, which defeats responsive testing.)

## Layout

```
integration_test/
  all_flows_test.dart        # aggregator — runs every flow in one build/launch
  pipeline_smoke_test.dart   # toolchain guard (bare widget, no app)
  run_macos.sh               # runs the aggregator
  BACKLOG.md                 # coverage not yet automated ("deep later")
  support/
    app_harness.dart         # bootGetman($) — boots the real app, isolated, desktop-sized
    mock_server.dart         # MockServer — hermetic localhost HTTP server
    mock_ws_server.dart      # MockWebSocketServer (echo) + sseResponder(...) for realtime
    actions.dart             # enterUrl / tapSend / sendTo / waitForStatus / newTab /
                             # setMethod / setRequestKind / openRequestTab / openResponseTab /
                             # openSideMenuTab / setParam / setHeader / setBodyType /
                             # enterPromptText / openSettings / openEnvironmentSelector
  flows/
    smoke_test.dart                 # app boots to the tabs view
    request_send_test.dart          # send a GET → render the 200 response
    json_fold_test.dart             # JSON response shows the fold gutter
    variable_substitution_test.dart # {{$timestamp}} resolves before sending
    tabs_test.dart                  # open/close tabs + cURL paste
    request_config_test.dart        # method + query param + header are sent
    history_test.dart               # send → lands in HISTORY → re-send
    collections_test.dart           # save request / create folder / delete via menu
    environments_test.dart          # create env + variable → active → resolves on send
    chaining_rules_test.dart        # assertion pass/fail + extraction capture in TESTS
    cookies_test.dart               # Set-Cookie → response COOKIES + jar manager + delete
    realtime_ws_test.dart           # WS connect/send/echo/disconnect (mock echo server)
    realtime_sse_test.dart          # SSE connect → streamed events (mock event-stream)
    auth_test.dart                  # bearer token → Authorization header
    code_gen_test.dart              # "Generate code" → cURL snippet
    settings_test.dart              # switch theme + toggle dark mode
    response_views_test.dart        # metadata + pretty/raw toggle + headers tab
    command_palette_test.dart       # (drafted, NOT registered — see BACKLOG.md)
```

Stable test anchors live as intentional `ValueKey`s in `lib/` (e.g.
`add_tab_button`, `method_selector`, `reqtab_tab_<LABEL>`, `resptab_tab_<LABEL>`,
`param_key_<i>` / `header_val_<i>`, `auth_type_dropdown`, `realtime_connect_button`,
`theme_dropdown`, `cookies_manage_button`, `node_menu_<id>`). Prefer these or
verbatim UI labels; add a new key in `lib/` only when there's no stable anchor.

## Adding a new flow

1. Create `flows/<feature>_test.dart`.
2. Register it in `all_flows_test.dart` (import it with a prefix and call its
   `main()`) so the full-suite run picks it up.
3. Start with the skeleton:

   ```dart
   import 'package:flutter_test/flutter_test.dart';
   import 'package:integration_test/integration_test.dart';
   import 'package:patrol_finders/patrol_finders.dart';

   import '../support/actions.dart';
   import '../support/app_harness.dart';
   import '../support/mock_server.dart';

   void main() {
     IntegrationTestWidgetsFlutterBinding.ensureInitialized();

     patrolWidgetTest('describe the user-visible behaviour', ($) async {
       final server = await MockServer.start(json: {'ok': true});
       addTearDown(server.close);

       await bootGetman($);
       // ... drive via `$` and the helpers in support/actions.dart ...
     });
   }
   ```

4. Prefer stable finders: existing `ValueKey`s (`url_field`, `send`, `tabs`,
   `tab_<id>`, …) or verbatim UI labels. If a widget you need has no stable
   anchor, add a `ValueKey` to it in `lib/` (keep these few and intentional).
5. After tapping **SEND**, don't `pumpAndSettle` (the response-pending shimmer
   animates forever) — use `await waitForStatus($, 200)` or
   `.waitUntilVisible()`, which pump without requiring a settle.

## Out of scope (for now)

- Native file-dialog flows (import/export, file body pick, save-to-file) — need
  native automation, which isn't available on macOS desktop.
- Mobile (iOS/Android) targets.
- CI wiring — run locally before publishing.

See [`BACKLOG.md`](BACKLOG.md) for the full list of not-yet-automated coverage
(command palette, saved examples, drag-and-drop, deeper settings/error states,
…) with a suggested approach per item.

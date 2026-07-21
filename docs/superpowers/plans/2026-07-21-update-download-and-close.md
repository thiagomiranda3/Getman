# Update Download-and-Close Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Windows/Linux, UPDATE NOW confirms "close and update", downloads the installer in-app to the Downloads folder behind a blocking progress dialog, then auto-launches the installer and quits Getman. macOS keeps the browser hand-off.

**Architecture:** Reuse `updat`'s download machinery (already a dependency), orchestrated by `update_gate_io.dart` with `openOnDownload`/`closeOnInstall` OFF so we control the terminal sequence (launch installer → flush tabs → `exit(0)`). The web-safe `UpdateController` gains an `installsInApp` flag so the platform-agnostic `UpdateDialog` can branch without importing `dart:io`.

**Tech Stack:** Flutter (pinned via `.fvmrc` — always `fvm flutter` / `fvm dart`), `updat` 1.4.0, `path_provider`, `flutter_bloc`, mocktail.

**Spec:** `docs/superpowers/specs/2026-07-21-update-download-and-close-design.md`

## Global Constraints

- **Always `fvm flutter …` / `fvm dart …`** — never plain `flutter`/`dart`.
- **`package:getman/…` imports everywhere** — no relative imports.
- Every new/edited `lib/` file keeps an accurate opening `//` header (`file_header_required` lint).
- Theme adherence: sizes/paddings/font sizes via `context.appLayout` etc. — never hardcoded.
- `discarded_futures` is a warning-level lint: wrap fire-and-forget futures in `unawaited(…)` (`dart:async`).
- Snackbars only via `showAppSnackBar(context, …)`; confirmations only via `ConfirmDialog.show(…)`.
- `print`/`debugPrint` rules: non-bloc layers use `debugPrint`; BLoCs use `dart:developer` `log`.
- `dart:io`/`updat`/`package_info_plus`/`path_provider` imports allowed ONLY in `*_io.dart` files (`platform_io_outside_io_files` lint). All gate work stays in `update_gate_io.dart`.
- UI copy is load-bearing for the wiki task — use these labels verbatim: `CLOSE AND UPDATE?`, `DOWNLOAD AND CLOSE`, `CANCEL`, `DOWNLOADING UPDATE…`, `UPDATE NOW`.
- Run feature tests with: `fvm flutter test test/features/updates -r compact`.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013mhumtQgzotqiYH9g5CVyS
  ```

---

### Task 1: `installsInApp` flag on `UpdateController`

**Files:**
- Modify: `lib/features/updates/presentation/update_controller.dart`
- Test: `test/features/updates/presentation/update_controller_test.dart`

**Interfaces:**
- Produces: `UpdateController.installsInApp` — a plain `bool` field, default `false`, no `notifyListeners` (set once by the io gate at startup, before any dialog exists). Tasks 2 and 5 read/write it.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/features/updates/presentation/update_controller_test.dart` (the file already has a `setUp` creating `controller`):

```dart
  test('installsInApp defaults to false (browser hand-off is the default)', () {
    expect(controller.installsInApp, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/update_controller_test.dart -r compact`
Expected: FAIL — compile error, `installsInApp` isn't defined.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/updates/presentation/update_controller.dart`, add after the `cachedRelease` field:

```dart
  /// True when this platform installs updates in-app (Windows/Linux: download
  /// to the Downloads folder, then auto-launch + quit) rather than handing
  /// the download to the browser (macOS, web). Set once by the io gate at
  /// startup — a plain field, no [notifyListeners] needed.
  bool installsInApp = false;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/updates/presentation/update_controller_test.dart -r compact`
Expected: PASS (all tests in file).

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/update_controller.dart test/features/updates/presentation/update_controller_test.dart
git commit -m "feat: add UpdateController.installsInApp platform flag"
```

---

### Task 2: UpdateDialog confirm-close flow + platform-aware note text

**Files:**
- Modify: `lib/features/updates/presentation/widgets/update_dialog.dart`
- Test: `test/features/updates/presentation/widgets/update_dialog_test.dart`

**Interfaces:**
- Consumes: `UpdateController.installsInApp` (Task 1), `ConfirmDialog.show` from `package:getman/core/ui/widgets/confirm_dialog.dart` (existing atom — signature: `show(context, {required String title, required String message, required VoidCallback onConfirm, String confirmLabel, String cancelLabel, bool destructive})`; it pops itself BEFORE running `onConfirm`).
- Produces: UPDATE NOW behavior — when `installsInApp` is true, tapping UPDATE NOW shows the ConfirmDialog *on top of* the still-open update dialog; CANCEL keeps the update dialog; DOWNLOAD AND CLOSE pops the update dialog then calls `controller.startUpdate`. When false, behavior is unchanged (startUpdate + pop immediately).

- [ ] **Step 1: Write the failing tests**

In `test/features/updates/presentation/widgets/update_dialog_test.dart`, first extract a host-widget helper (the existing "UPDATE NOW invokes startUpdate" test builds this inline — refactor it to use the helper too):

```dart
Widget _host(UpdateController controller) {
  return MaterialApp(
    theme: brutalistTheme(Brightness.light),
    home: ChangeNotifierProvider<UpdateController>.value(
      value: controller,
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ChangeNotifierProvider<UpdateController>.value(
                  value: controller,
                  child: const UpdateDialog(
                    latestVersion: '1.1.0',
                    currentVersion: '1.0.0',
                    changelog: null,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}
```

Then add these tests inside `main()`:

```dart
  testWidgets('in-app flow: UPDATE NOW asks for confirmation first', (t) async {
    final controller = UpdateController(_FakeUpdateRepository())
      ..installsInApp = true;
    var started = false;
    controller.startUpdate = () async => started = true;

    await t.pumpWidget(_host(controller));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('update_now_button')));
    await t.pumpAndSettle();

    expect(find.text('CLOSE AND UPDATE?'), findsOneWidget);
    expect(find.text('DOWNLOAD AND CLOSE'), findsOneWidget);
    // Update dialog still open behind the confirm box; nothing started.
    expect(find.byKey(const ValueKey('update_now_button')), findsOneWidget);
    expect(started, isFalse);
  });

  testWidgets('in-app flow: CANCEL keeps the update dialog, starts nothing', (
    t,
  ) async {
    final controller = UpdateController(_FakeUpdateRepository())
      ..installsInApp = true;
    var started = false;
    controller.startUpdate = () async => started = true;

    await t.pumpWidget(_host(controller));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('update_now_button')));
    await t.pumpAndSettle();

    await t.tap(find.text('CANCEL'));
    await t.pumpAndSettle();

    expect(find.text('CLOSE AND UPDATE?'), findsNothing);
    expect(find.byKey(const ValueKey('update_now_button')), findsOneWidget);
    expect(started, isFalse);
  });

  testWidgets(
    'in-app flow: DOWNLOAD AND CLOSE starts the update and closes the dialog',
    (t) async {
      final controller = UpdateController(_FakeUpdateRepository())
        ..installsInApp = true;
      var started = false;
      controller.startUpdate = () async => started = true;

      await t.pumpWidget(_host(controller));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('update_now_button')));
      await t.pumpAndSettle();

      await t.tap(find.text('DOWNLOAD AND CLOSE'));
      await t.pumpAndSettle();

      expect(started, isTrue);
      expect(find.byKey(const ValueKey('update_now_button')), findsNothing);
      expect(find.text('CLOSE AND UPDATE?'), findsNothing);
    },
  );

  testWidgets('note text is platform-aware', (t) async {
    final inApp = UpdateController(_FakeUpdateRepository())
      ..installsInApp = true;
    await t.pumpWidget(_host(inApp));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.textContaining('Downloads folder'), findsOneWidget);
    expect(find.textContaining('browser'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_dialog_test.dart -r compact`
Expected: the 4 new tests FAIL (no 'CLOSE AND UPDATE?' appears; note text still says browser); the 2 existing tests still PASS.

- [ ] **Step 3: Implement**

In `lib/features/updates/presentation/widgets/update_dialog.dart`:

a) Replace the file header (lines 1–3) with:

```dart
// Update-available dialog (SKIP THIS VERSION / LATER / UPDATE NOW). UPDATE
// NOW branches on UpdateController.installsInApp: Windows/Linux confirm
// "close and update" then download in-app; macOS hands off to the browser.
```

b) Add the import `package:getman/core/ui/widgets/confirm_dialog.dart` (keep imports alphabetized — `directives_ordering`).

c) Update the class doc's action sentence to:

```dart
/// Themed dialog shown when an update is available. Shows the version line,
/// optional changelog, a note about how the download works, and three actions:
/// SKIP THIS VERSION, LATER, and UPDATE NOW. When
/// [UpdateController.installsInApp] is true (Windows/Linux) UPDATE NOW first
/// confirms via [ConfirmDialog] that Getman may close, then starts the in-app
/// download (see `update_gate_io.dart`); otherwise it opens the release
/// download in the user's browser and closes the dialog.
```

d) In `build`, read the flag once and pass it down:

```dart
  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final controller = _controller(context);
    final installsInApp = controller?.installsInApp ?? false;

    return ResponsiveDialogScaffold(
      title: const Text('UPDATE AVAILABLE'),
      content: _DialogBody(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        changelog: changelog,
        layout: layout,
        installsInApp: installsInApp,
      ),
```

e) Replace the UPDATE NOW button's `onPressed`:

```dart
        TextButton(
          key: const ValueKey('update_now_button'),
          onPressed: () {
            if (installsInApp) {
              unawaited(
                ConfirmDialog.show(
                  context,
                  title: 'CLOSE AND UPDATE?',
                  message:
                      'Getman will download the update to your Downloads '
                      'folder and then close itself so the installer can '
                      'run. Continue?',
                  confirmLabel: 'DOWNLOAD AND CLOSE',
                  destructive: false,
                  // ConfirmDialog pops itself before onConfirm, so `context`
                  // (the still-mounted update dialog) is safe to pop here.
                  onConfirm: () {
                    Navigator.pop(context);
                    unawaited(controller?.startUpdate?.call());
                  },
                ),
              );
            } else {
              unawaited(controller?.startUpdate?.call());
              Navigator.pop(context);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
          child: const Text('UPDATE NOW'),
        ),
```

f) `_DialogBody`: add the field + constructor param `required this.installsInApp,` / `final bool installsInApp;`, and replace the final note `Text` with:

```dart
        Text(
          installsInApp
              ? 'UPDATE NOW downloads the installer to your Downloads folder '
                    'and closes Getman so the installer can run. Getman is '
                    'not code-signed, so your OS may warn before running it.'
              : 'UPDATE NOW opens the download in your browser. Getman is '
                    'not code-signed, so your OS may warn on first launch — '
                    'allow it via right-click → Open (macOS) or More info → '
                    'Run anyway (Windows).',
          style: TextStyle(fontSize: layout.fontSizeSmall),
        ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_dialog_test.dart -r compact`
Expected: ALL PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/widgets/update_dialog.dart test/features/updates/presentation/widgets/update_dialog_test.dart
git commit -m "feat: confirm close-and-update before in-app download in UpdateDialog"
```

---

### Task 3: Blocking download-progress dialog

**Files:**
- Create: `lib/features/updates/presentation/widgets/update_download_dialog.dart`
- Test: `test/features/updates/presentation/widgets/update_download_dialog_test.dart`

**Interfaces:**
- Produces: `UpdateDownloadDialog` with `static Future<void> show(BuildContext context)` — non-dismissible modal; Task 5's gate calls `show` when the download starts and pops it (via the navigator) on failure.

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/presentation/widgets/update_download_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/updates/presentation/widgets/update_download_dialog.dart';

void main() {
  Widget host() {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => UpdateDownloadDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the blocking download dialog with a spinner', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();

    expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('cannot be dismissed by barrier tap or Escape', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();

    // Barrier tap (top-left corner is outside the dialog card).
    await t.tapAt(const Offset(5, 5));
    await t.pump();
    expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);

    // Escape key.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);
  });
}
```

Note: use `t.pump()` (not `pumpAndSettle`) — the indeterminate spinner animates forever, so `pumpAndSettle` would time out.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_download_dialog_test.dart -r compact`
Expected: FAIL — compile error, file doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/features/updates/presentation/widgets/update_download_dialog.dart`:

```dart
// Blocking "DOWNLOADING UPDATE…" progress dialog for the Windows/Linux
// in-app update flow; deliberately non-dismissible — the user already
// confirmed Getman will close when the download finishes.

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

/// Modal indeterminate-progress dialog shown while the update installer
/// downloads. No actions and no dismissal ([PopScope] blocks Escape/back and
/// the barrier is non-dismissible): the update gate pops it on download
/// failure, and on success the app quits with it still up. Indeterminate
/// because `updat` downloads with a single `http.get` — no progress stream.
class UpdateDownloadDialog extends StatelessWidget {
  const UpdateDownloadDialog({super.key});

  /// Shows the dialog; the returned future completes when the update gate
  /// pops it (download failure) — on success the app exits first.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDownloadDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return PopScope(
      canPop: false,
      child: ResponsiveDialogScaffold(
        title: const Text('DOWNLOADING UPDATE…'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(width: layout.tabSpacing),
            Flexible(
              child: Text(
                'Getman will close and run the installer when the download '
                'finishes.',
                style: TextStyle(fontSize: layout.fontSizeNormal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_download_dialog_test.dart -r compact`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/widgets/update_download_dialog.dart test/features/updates/presentation/widgets/update_download_dialog_test.dart
git commit -m "feat: add blocking UpdateDownloadDialog for the in-app update flow"
```

---

### Task 4: Terminal sequence — `finishInAppUpdate` + `launchDownloadedInstaller`

**Files:**
- Modify: `lib/features/updates/presentation/update_gate_io.dart` (top-level additions only — no widget changes yet)
- Test: `test/features/updates/presentation/update_gate_io_test.dart`

**Interfaces:**
- Produces (Task 5 consumes both):
  - `enum UpdateFinishResult { quitting, launchFailed }`
  - `Future<UpdateFinishResult> finishInAppUpdate({required Future<void> Function() launchInstaller, required Future<void> Function() flushTabs, required void Function() quit})`
  - `Future<void> launchDownloadedInstaller(File installer)`

**Ordering rationale (this is a deliberate spec amendment, documented in Task 6):** launch comes FIRST. Flushing first would `close()` the TabsBloc; if the launch then failed, the app would stay open with dead tab persistence. A failed launch must leave the app fully intact.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/updates/presentation/update_gate_io_test.dart` (inside `main()`, after the existing tests):

```dart
  group('finishInAppUpdate', () {
    test('launches, then flushes tabs, then quits — in that order', () async {
      final calls = <String>[];
      final result = await finishInAppUpdate(
        launchInstaller: () async => calls.add('launch'),
        flushTabs: () async => calls.add('flush'),
        quit: () => calls.add('quit'),
      );
      expect(result, UpdateFinishResult.quitting);
      expect(calls, ['launch', 'flush', 'quit']);
    });

    test('a failed launch keeps the app alive: no flush, no quit', () async {
      final calls = <String>[];
      final result = await finishInAppUpdate(
        launchInstaller: () async => throw Exception('no such file'),
        flushTabs: () async => calls.add('flush'),
        quit: () => calls.add('quit'),
      );
      expect(result, UpdateFinishResult.launchFailed);
      expect(calls, isEmpty);
    });

    test('a failed tab flush still quits (best-effort flush)', () async {
      var quitCalled = false;
      final result = await finishInAppUpdate(
        launchInstaller: () async {},
        flushTabs: () async => throw Exception('hive is gone'),
        quit: () => quitCalled = true,
      );
      expect(result, UpdateFinishResult.quitting);
      expect(quitCalled, isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/update_gate_io_test.dart -r compact`
Expected: FAIL — compile error, `finishInAppUpdate` / `UpdateFinishResult` undefined.

- [ ] **Step 3: Implement**

Add at the BOTTOM of `lib/features/updates/presentation/update_gate_io.dart` (after the `_UpdateGateState` class). Also add `import 'package:flutter/foundation.dart' show visibleForTesting;` — NO: `visibleForTesting` comes from `package:meta` via flutter's `material.dart` which is already imported, so no new import is needed.

```dart
/// Outcome of [finishInAppUpdate]: tells the gate (and tests) apart "the app
/// is about to exit" from "installer launch failed, keep the app alive".
enum UpdateFinishResult { quitting, launchFailed }

/// Terminal sequence of the in-app update: launch the downloaded installer,
/// best-effort flush unsaved tabs, then quit.
///
/// Launch comes FIRST deliberately — flushing first would `close()` the
/// TabsBloc, and if the launch then failed the app would sit open with dead
/// tab persistence. A failed launch here leaves the app fully intact; a
/// failed flush never blocks the quit (losing <10 s of tab edits beats
/// stranding the update with the installer already running).
@visibleForTesting
Future<UpdateFinishResult> finishInAppUpdate({
  required Future<void> Function() launchInstaller,
  required Future<void> Function() flushTabs,
  required void Function() quit,
}) async {
  try {
    await launchInstaller();
  } on Object {
    return UpdateFinishResult.launchFailed;
  }
  try {
    await flushTabs();
  } on Object {
    // Best-effort only — see doc above.
  }
  quit();
  return UpdateFinishResult.quitting;
}

/// Launches the downloaded installer. Windows: start the Inno Setup `.exe`
/// detached. Linux: `chmod +x` first, then start the AppImage detached — a
/// fresh download has no execute bit, so a plain file-open would not run it.
/// Throws on failure so [finishInAppUpdate] can keep the app alive.
@visibleForTesting
Future<void> launchDownloadedInstaller(File installer) async {
  if (Platform.isLinux) {
    final chmod = await Process.run('chmod', ['+x', installer.path]);
    if (chmod.exitCode != 0) {
      throw ProcessException(
        'chmod',
        ['+x', installer.path],
        chmod.stderr.toString(),
        chmod.exitCode,
      );
    }
  }
  await Process.start(
    installer.path,
    const <String>[],
    mode: ProcessStartMode.detached,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/updates/presentation/update_gate_io_test.dart -r compact`
Expected: ALL PASS (existing 3 + new 3).

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/update_gate_io.dart test/features/updates/presentation/update_gate_io_test.dart
git commit -m "feat: add launch-flush-quit terminal sequence for in-app updates"
```

---

### Task 5: Gate wiring — platform flag, download orchestration, status routing

**Files:**
- Modify: `lib/features/updates/presentation/update_gate_io.dart`
- Test: `test/features/updates/presentation/update_gate_io_test.dart`

**Interfaces:**
- Consumes: `UpdateController.installsInApp` (Task 1), `UpdateDownloadDialog.show` (Task 3), `finishInAppUpdate` / `launchDownloadedInstaller` / `UpdateFinishResult` (Task 4), `TabsBloc` from `package:getman/features/tabs/presentation/bloc/tabs_bloc.dart` (provided app-wide in `main.dart`; its `close()` cancels the 10 s debounce and flushes dirty tabs).
- Produces: `UpdateGate` constructor test seams `debugInstallsInApp` (`bool?`), `debugInstallerLauncher` (`Future<void> Function(File)?`), `debugQuit` (`void Function()?`).

- [ ] **Step 1: Write the failing widget test**

Append to `test/features/updates/presentation/update_gate_io_test.dart` inside `main()`:

```dart
  testWidgets(
    'in-app flow: confirm shows the blocking dialog; a failed download pops '
    'it, shows the error snackbar, and never quits',
    (tester) async {
      final controller = UpdateController(
        _ReleaseRepo(
          const ReleaseInfo(
            version: '99.0.0',
            changelog: null,
            assetUrl: 'https://example.com/getman-99.0.0.exe',
          ),
        ),
      );
      final bloc = buildSettingsBloc();
      var quitCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: ChangeNotifierProvider<UpdateController>.value(
            value: controller,
            child: BlocProvider.value(
              value: bloc,
              child: Scaffold(
                body: UpdateGate(
                  debugInstallsInApp: true,
                  debugQuit: () => quitCalled = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Startup check found 99.0.0 → update dialog prompted.
      await tester.tap(find.byKey(const ValueKey('update_now_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DOWNLOAD AND CLOSE'));
      await tester.pump();

      // The blocking dialog is up while updat downloads.
      expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);

      // flutter_test's HttpClient 400s every request, so the download fails:
      // dialog popped, snackbar shown, app still alive.
      await tester.pumpAndSettle();
      expect(find.text('DOWNLOADING UPDATE…'), findsNothing);
      expect(find.text("Couldn't download the update."), findsOneWidget);
      expect(quitCalled, isFalse);
    },
  );
```

Timing note for the implementer: the single `pump()` after DOWNLOAD AND CLOSE should render the dialog because `_startInAppDownload` pushes it synchronously in the confirm handler chain. If the download error lands in the same frame on your machine, replace the intermediate assertion with a comment and keep the post-`pumpAndSettle` assertions — those are the load-bearing ones.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/update_gate_io_test.dart -r compact`
Expected: the new test FAILS (no `debugInstallsInApp` param → compile error).

- [ ] **Step 3: Implement the gate changes**

All in `lib/features/updates/presentation/update_gate_io.dart`:

a) Replace the file header (lines 1–8) with:

```dart
// Native-only auto-update gate: the SOLE importer of dart:io, package:updat,
// package_info_plus, and path_provider (the web-safety gate — see
// update_gate.dart's conditional export to update_gate_stub.dart on web).
// Two flows: macOS hands the download to the browser (a file downloaded by
// this sandboxed, unsigned app carries a strict com.apple.quarantine flag
// that Gatekeeper reports as "damaged", and the sandbox forbids clearing it);
// Windows/Linux download in-app via updat to the Downloads folder, then
// launch the installer and quit (finishInAppUpdate). See class doc below.
```

b) Add imports (alphabetized within the existing block):

```dart
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/updates/presentation/widgets/update_download_dialog.dart';
import 'package:path_provider/path_provider.dart';
```

c) Update the class doc and add the seams:

```dart
/// Invisible widget mounted in `MainScreen`. Hosts one `UpdatWidget` for the
/// GitHub version *check* (and, on Windows/Linux, the in-app download),
/// bridges its callbacks into [UpdateController], and shows the themed
/// [UpdateDialog] / snackbars per the prompt decision.
///
/// macOS: the download is handed to the user's browser (see
/// `_openDownloadInBrowser`) — never performed in-process. Windows/Linux:
/// updat downloads the installer (blocking [UpdateDownloadDialog]), then
/// [finishInAppUpdate] launches it, flushes tabs, and quits.
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    this.debugInstallsInApp,
    this.debugInstallerLauncher,
    this.debugQuit,
  });

  /// Test seams — widget tests run on a macOS host, so the Windows/Linux
  /// in-app flow is unreachable without overrides. All null in production.
  @visibleForTesting
  final bool? debugInstallsInApp;

  @visibleForTesting
  final Future<void> Function(File installer)? debugInstallerLauncher;

  @visibleForTesting
  final void Function()? debugQuit;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}
```

d) In `_UpdateGateState`, add fields + a getter after `_currentVersion`:

```dart
  /// The installer download target, remembered by [_downloadLocationFor] so
  /// the finish/error paths can launch it or name it in messages.
  File? _installerFile;

  /// True from the user's "download and close" confirmation until the
  /// download resolves. Routes `_onStatus`'s readyToInstall/error into the
  /// in-app flow (a failed version *check* also emits `error` — this flag
  /// tells the two apart).
  bool _inAppDownloadInFlight = false;

  /// Whether the blocking [UpdateDownloadDialog] is on screen, so the error
  /// path pops exactly it and nothing else.
  bool _downloadDialogOpen = false;

  /// updat's real in-process downloader, captured from the chip builder.
  void Function()? _updatStartUpdate;

  bool get _installsInApp =>
      widget.debugInstallsInApp ?? (Platform.isWindows || Platform.isLinux);
```

e) In `initState`, publish the flag to the web-safe controller (before `_loadVersion`):

```dart
  @override
  void initState() {
    super.initState();
    if (_supported) {
      context.read<UpdateController>().installsInApp = _installsInApp;
      unawaited(_loadVersion());
    }
  }
```

f) In the `UpdatWidget` construction: pass the download location hook, and fix the stale `getBinaryUrl` comment:

```dart
      // Used by updat's in-app downloader on Windows/Linux. On macOS the
      // browser hand-off means it's never invoked.
      getBinaryUrl: (_) async => controller.cachedRelease?.assetUrl ?? '',
      getDownloadFileLocation: _downloadLocationFor,
```

g) In the chip builder, capture updat's downloader and branch `startUpdate` per platform (replace the existing `controller..triggerCheck…` cascade; keep the existing comment about assignment order):

```dart
            _updatStartUpdate = startUpdate;
            controller
              ..triggerCheck = checkForUpdate
              ..dismiss = dismissUpdate
              ..startUpdate = () {
                return _installsInApp
                    ? _startInAppDownload()
                    : _openDownloadInBrowser(controller);
              };
```

h) Add the orchestration methods to `_UpdateGateState` (after `_openDownloadInBrowser`):

```dart
  /// Computes (and remembers) where the installer download lands: the user's
  /// Downloads folder, falling back to the system temp dir when the platform
  /// reports none (some headless Linux setups; plugin-less tests). Must never
  /// throw — updat calls it OUTSIDE its own try/catch, so an exception here
  /// would strand the status at `downloading` with the dialog up forever.
  Future<File> _downloadLocationFor(String? latestVersion) async {
    final url = context.read<UpdateController>().cachedRelease?.assetUrl ?? '';
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } on Object {
      downloads = null;
    }
    final dir = downloads ?? Directory.systemTemp;
    final ext = url.contains('.') ? url.split('.').last : 'bin';
    final file = File(
      '${dir.path}${Platform.pathSeparator}$_appName-$latestVersion.$ext',
    );
    _installerFile = file;
    return file;
  }

  /// Confirmed in-app flow: block the UI with [UpdateDownloadDialog] and hand
  /// off to updat's downloader. Resolution arrives via [_onStatus]
  /// (readyToInstall → [_finishInAppUpdate]; error → pop + snackbar).
  Future<void> _startInAppDownload() async {
    _inAppDownloadInFlight = true;
    _downloadDialogOpen = true;
    unawaited(
      UpdateDownloadDialog.show(
        context,
      ).whenComplete(() => _downloadDialogOpen = false),
    );
    _updatStartUpdate?.call();
  }

  void _popDownloadDialogIfOpen() {
    if (!_downloadDialogOpen) return;
    _downloadDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Download finished: run the terminal sequence (launch installer → flush
  /// tabs → quit). Only the launch-failure outcome returns control here —
  /// the app must then stay fully usable, with the installer path surfaced.
  Future<void> _finishInAppUpdate() async {
    final installer = _installerFile;
    if (installer == null) return;
    TabsBloc? tabs;
    try {
      tabs = context.read<TabsBloc>();
    } on Object {
      tabs = null; // Tests may mount the gate without a TabsBloc.
    }
    final launcher = widget.debugInstallerLauncher ?? launchDownloadedInstaller;
    final result = await finishInAppUpdate(
      launchInstaller: () => launcher(installer),
      flushTabs: () async => tabs?.close(),
      quit: widget.debugQuit ?? _exitApp,
    );
    if (!mounted || result != UpdateFinishResult.launchFailed) return;
    _popDownloadDialogIfOpen();
    showAppSnackBar(
      context,
      'Update downloaded to ${installer.path}, but it could not be opened — '
      'run it manually.',
    );
  }

  static Never _exitApp() => exit(0);
```

i) In `_onStatus`, replace the final "never occur" comment + fall-through group so `readyToInstall` and the in-app `error` are handled:

```dart
        case UpdatePhase.error:
          if (_inAppDownloadInFlight) {
            // The in-app download failed (not a version check): unblock the
            // UI and keep the app running.
            _inAppDownloadInFlight = false;
            _popDownloadDialogIfOpen();
            showAppSnackBar(context, "Couldn't download the update.");
          } else if (controller.manualInFlight) {
            // A failed *check* only matters to surface when the user
            // explicitly pressed "Check for updates"; background checks stay
            // quiet.
            controller.manualInFlight = false;
            showAppSnackBar(context, "Couldn't check for updates.");
          }
        case UpdatePhase.readyToInstall:
          if (_inAppDownloadInFlight) {
            _inAppDownloadInFlight = false;
            unawaited(_finishInAppUpdate());
          }
        // downloading is surfaced by the blocking dialog _startInAppDownload
        // already pushed; the rest need no side effects.
        case UpdatePhase.idle:
        case UpdatePhase.checking:
        case UpdatePhase.downloading:
        case UpdatePhase.dismissed:
          break;
```

(The existing `available` / `upToDate` cases stay exactly as they are.)

- [ ] **Step 4: Run the whole updates feature suite**

Run: `fvm flutter test test/features/updates -r compact`
Expected: ALL PASS — including the untouched C1/C2/regression tests (macOS host → `_installsInApp` false → browser path unchanged) and Task 2/3/4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/update_gate_io.dart test/features/updates/presentation/update_gate_io_test.dart
git commit -m "feat: in-app download-and-close update flow on Windows/Linux"
```

---

### Task 6: Documentation sync (architecture doc, spec amendment, CODEMAP)

**Files:**
- Modify: `docs/architecture/settings-history-updates.md`
- Modify: `docs/superpowers/specs/2026-07-21-update-download-and-close-design.md`
- Modify: `docs/CODEMAP.md`

- [ ] **Step 1: Rewrite the auto-update section of `docs/architecture/settings-history-updates.md`**

Replace the paragraph under `## Auto-update (GitHub-release)` (keep the `### Web-safety gate` and `### Auto-update fields` subsections, but update the gate note as shown):

```markdown
On startup (when `checkForUpdatesOnStartup` is `true`) one `releases/latest`
check via `GithubReleaseDataSource`; if a newer version is found, `UpdateDialog`
prompts Update now / Skip this version / Later. Logic lives in
`update_decision.dart` (`isNewerVersion` + `shouldPromptForUpdate`);
`UpdateController` (a `ChangeNotifier`) drives dialog state and is provided via
`ChangeNotifierProvider` above `MaterialApp`. A GENERAL-tab toggle + "CHECK FOR
UPDATES" button are in `UpdateSettingsSection`. Per-platform installers: `.dmg`
(macOS), Inno Setup `.exe` (Windows), `AppImage` (Linux).

UPDATE NOW is platform-split via `UpdateController.installsInApp` (set once by
the io gate at startup):

- **macOS** (`installsInApp == false`): opens the asset URL in the browser —
  an in-app download by the sandboxed, unsigned app carries a strict
  `com.apple.quarantine` flag that Gatekeeper reports as "damaged", and the
  sandbox can't clear it (the v1.4.1 fix; do not re-enable without
  signing/notarization).
- **Windows/Linux** (`installsInApp == true`): a `ConfirmDialog`
  ("CLOSE AND UPDATE?") warns that Getman will close; on confirm, `updat`
  downloads the installer to the user's Downloads folder behind the blocking
  `UpdateDownloadDialog`, then `finishInAppUpdate` runs **launch installer →
  flush tabs (`TabsBloc.close()`, cancels the 10 s debounce) → `exit(0)`**.
  Launch comes first deliberately: a failed launch must leave the app fully
  usable, and an early flush would have closed the TabsBloc. Linux gets a
  `chmod +x` before the AppImage starts. A failed download pops the dialog and
  snackbars; a failed launch surfaces the downloaded path. `updat`'s own
  `openOnDownload`/`closeOnInstall` stay **off** — its `closeOnInstall` calls
  `exit(0)` without flushing tabs.
```

And in the `### Web-safety gate` subsection, update the `update_gate_io.dart` bullet's parenthetical — it currently says the file does **not** import `path_provider`; it now does (for `getDownloadsDirectory`):

```markdown
- `update_gate_io.dart` — native only; the **sole importer of `updat`,
  `dart:io`, `package_info_plus`, and `path_provider`** (the latter for
  `getDownloadsDirectory` in the in-app download flow; the response media
  viewers' `*_io.dart` files also import it).
```

- [ ] **Step 2: Amend the spec's ordering**

In `docs/superpowers/specs/2026-07-21-update-download-and-close-design.md`, the "On success, in order" list says flush → launch → exit. Replace that numbered list with:

```markdown
4. On success, in order (*amended during planning — launch moved first: a
   failed launch must leave the app fully usable, and flushing first would
   have `close()`d the TabsBloc, killing tab persistence*):
   1. Launch the installer:
      - **Windows:** start the downloaded `.exe` detached.
      - **Linux:** `chmod +x` the AppImage, then start it detached
        (a plain file-open does not execute a fresh AppImage).
   2. Flush unsaved tabs — `TabsBloc.close()` (cancels the 10 s debounce and
      writes dirty tabs; best-effort — a failed flush never blocks the quit).
   3. `exit(0)`.
```

- [ ] **Step 3: Update CODEMAP**

In `docs/CODEMAP.md`:
- Line ~197 (`lib/features/updates/presentation/widgets` row): add `update_download_dialog.dart` → new cell text: `` `update_dialog.dart`, `update_download_dialog.dart` (blocking in-app download progress), `update_settings_section.dart`. ``
- Line ~351 (Auto-update flow step 5): replace the parenthetical `(UPDATE NOW opens the browser)` with `(UPDATE NOW: macOS opens the browser; Windows/Linux confirm, download in-app, launch the installer, and quit)`.

- [ ] **Step 4: Run the docs coverage test**

Run: `fvm flutter test test/docs -r compact` — if that path doesn't exist, find it with `grep -rln 'CODEMAP' test/ | head` and run the matching test file.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture/settings-history-updates.md docs/superpowers/specs/2026-07-21-update-download-and-close-design.md docs/CODEMAP.md
git commit -m "docs: document the Windows/Linux download-and-close update flow"
```

---

### Task 7: Full verification bar

**Files:** none (verification only).

- [ ] **Step 1: Run all four static-analysis passes + format + full test suite**

```bash
fvm flutter analyze
fvm dart run custom_lint
( cd tools/getman_lints/example && fvm dart run custom_lint )
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```

Expected: analyze `No issues found!`; custom_lint `No issues found!` (both); bloc lint `0 issues`; format `0 changed`; tests 100% green. Fix anything that surfaces (likely candidates: import ordering, `discarded_futures` on a missed future, line length from the long strings) and re-run until all clean.

- [ ] **Step 2: Commit any fixes**

```bash
git add -A && git commit -m "chore: verification-bar fixes for the update flow"
```

(Skip the commit if the tree is already clean.)

---

### Task 8: Wiki sync (mandate)

**Files:** external repo `https://github.com/thiagomiranda3/Getman.wiki.git` (branch `master`).

- [ ] **Step 1: Clone the wiki into the scratchpad and find the Auto-Update page**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git "$SCRATCHPAD/wiki"
ls "$SCRATCHPAD/wiki" | grep -i -e update -e auto
```

(`$SCRATCHPAD` = the session scratchpad directory. The page is likely `Auto-Update.md`; check `_Sidebar.md` if unsure.)

- [ ] **Step 2: Update the page**

Rewrite the "what UPDATE NOW does" portion to describe both flows, using verbatim UI labels. Content to convey (adapt to the page's existing voice/structure — read it first):

- **Windows / Linux:** clicking **UPDATE NOW** opens a confirmation box titled **CLOSE AND UPDATE?** explaining Getman will download the update to your Downloads folder and then close itself so the installer can run. **CANCEL** returns to the update dialog. **DOWNLOAD AND CLOSE** downloads the installer (`getman-<version>.exe` / `.AppImage`) behind a **DOWNLOADING UPDATE…** progress dialog; when it finishes, the installer opens automatically and Getman closes itself. If the download fails, Getman stays open and shows an error. Getman is not code-signed, so your OS may warn before running the installer.
- **macOS:** unchanged — **UPDATE NOW** opens the download in your browser (Getman can't safely download it in-app while unsigned); allow the app on first launch via right-click → Open.

- [ ] **Step 3: Commit and push the wiki**

```bash
cd "$SCRATCHPAD/wiki"
git add -A && git commit -m "docs: document the Windows/Linux download-and-close update flow" && git push origin master
```

Expected: push succeeds (gh/keyring auth is already set up for `thiagomiranda3`).

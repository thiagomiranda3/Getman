# Settings, history & auto-update

> Deep-dive for three smaller features: settings (the single app-wide record), history (read-only request log), and the GitHub-release auto-updater. Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md. Every `SettingsModel` field is catalogued in docs/architecture/persistence-hive.md.

## Settings

- Settings are loaded synchronously at boot (`settingsBox.get('current')`) and injected as `initialSettings`. There is **no `LoadSettings` event** — do not add one unless you also change boot.
- Every `Update*` event both saves and emits in the handler — settings (and collections) persist immediately.
- `SettingsBloc` has one handler per `Update*` event and holds no cross-feature references (e.g. the response-history limits ride on the `SendRequest` event, computed at dispatch — see docs/architecture/tabs-and-panels.md).
- UI is `settings_dialog.dart` (5 tabs: GENERAL / APPEARANCE / NETWORK / WORKSPACE, plus the shortcuts reference in `settings_shortcuts_tab.dart`); network changes reach the live client via `network_settings_listener.dart`.

## History

- History is **read-only from the UI**: writes happen only inside `SendRequestUseCase`. `HistoryBloc` has a single (internal) `HistoryUpdated` event and subscribes to `watchHistory()` on construction; the data source uses `Hive.Box.watch()` and emits on every box change. Don't add UI-dispatched history events without wiring real UI to them.
- **Dedup** in `HistoryLocalDataSourceImpl.addToHistory` is by request signature: `method + url + body` **plus the body-shape fields** `bodyType`, `graphqlVariables`, `bodyFilePath`, and `formFields` (so two GraphQL sends differing only in variables, or two different file uploads, are distinct history entries). Headers differences do not dedupe.
- **Trim** uses a `while` loop so lowering `historyLimit` actually shrinks the box.
- Ordering: the data source returns `box.values` in insertion order; the repository reverses so the UI gets newest-first.

## Auto-update (GitHub-release)

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
  `exit(0)` without flushing tabs. A 10-minute download-stall watchdog guards
  `updat`'s single unbounded `http.get`: on fire the dialog closes and a
  snackbar explains the timeout, with the app staying open.

### Web-safety gate

The platform gate keeps web builds clean via a conditional export:

- `update_gate.dart` — conditional export.
- `update_gate_io.dart` — native only; the **sole importer of `updat` and
  `package_info_plus`**, and one of the io-gated `*_io.dart` importers of
  `dart:io`/`path_provider` (the latter for `getDownloadsDirectory` in the
  in-app download flow; the response media viewers' `*_io.dart` files also
  import it).
- `update_gate_stub.dart` — web no-op.

This split is machine-enforced by the `platform_io_outside_io_files` custom lint (imports of `dart:io`/`updat`/`package_info_plus`/`path_provider` are forbidden outside `*_io.dart` files).

### Auto-update fields on SettingsModel

`checkForUpdatesOnStartup` at `HiveField(25)` (default `true`) and `skippedUpdateVersion` at `HiveField(26)` (nullable; set when the user picks "Skip this version" — never cleared, so a still-newer release re-prompts because `shouldPromptForUpdate` suppresses only the exact skipped version). See docs/architecture/persistence-hive.md for the full field ledger.

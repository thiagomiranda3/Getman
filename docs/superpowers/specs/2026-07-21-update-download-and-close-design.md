# Update download-and-close flow — design

**Date:** 2026-07-21
**Status:** Approved
**Feature:** In-app installer download with confirm-close, auto-open, and auto-quit (Windows/Linux)

## Problem

Today UPDATE NOW hands the release download to the user's browser on every
platform. The user then has to notice the download finishing, find the file,
quit Getman, and run the installer by hand. On Windows and Linux none of that
indirection is necessary — the `updat` package already in the app can download
the installer and launch it. (On macOS the browser hand-off is load-bearing:
a file downloaded by the sandboxed, unsigned app carries a strict
`com.apple.quarantine` flag that Gatekeeper escalates to "damaged", and the
sandbox cannot clear it — the exact bug fixed in v1.4.1. macOS behavior does
not change.)

## Decisions made during brainstorming

- **macOS keeps the browser hand-off** (no in-app download, no auto-quit).
- **Blocking indeterminate progress dialog** during the download — the user
  just agreed to close the app, so blocking is honest and nothing new is lost.
  No percentage is available (`updat` downloads via a single `http.get`).
- **Approach A**: reuse `updat`'s download/launch machinery, orchestrated by
  our code, rather than a custom `dio` downloader (B) or browser-everywhere (C).

## UX flow

### Windows / Linux

1. Update dialog (unchanged) → user clicks **UPDATE NOW**.
2. `ConfirmDialog.show` appears **on top of** the update dialog:
   - Title: `CLOSE AND UPDATE?`
   - Message: "Getman will download the update to your Downloads folder and
     then close itself so the installer can run. Continue?"
   - **Cancel** → confirm box closes, update dialog is still open, nothing
     downloaded.
   - **Confirm** → update dialog closes and the download starts.
3. A non-dismissible themed **DOWNLOADING UPDATE…** dialog (indeterminate
   spinner) blocks the UI. `updat` downloads the installer to the user's
   **Downloads folder** as `getman-<version>.exe` / `getman-<version>.AppImage`.
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

### macOS

Unchanged: UPDATE NOW opens the asset URL in the browser. One fix that falls
out: the update dialog's note text currently claims "UPDATE NOW opens the
download in your browser" on *all* platforms — it becomes platform-aware
(Windows/Linux: "UPDATE NOW downloads the installer to your Downloads folder
and closes Getman to run it.").

## Code changes

| File | Change |
|---|---|
| `update_controller.dart` (web-safe) | New `installsInApp` flag (default `false`), set by the gate on Windows/Linux. This is how the platform-agnostic dialog picks its flow without importing `dart:io` (`platform_io_outside_io_files` stays happy). |
| `update_dialog.dart` | UPDATE NOW checks `installsInApp` → shows the ConfirmDialog first (cancel keeps the update dialog open); browser path untouched. Note text becomes flag-aware. |
| `update_gate_io.dart` | Keeps `openOnDownload: false` and `closeOnInstall: false` and orchestrates itself: captures updat's real `startUpdate`, supplies `getDownloadFileLocation` (so the installer path is known for launch/chmod/error messages), tracks an `_inAppDownloadInFlight` flag so `_onStatus` routes `downloading` → show progress dialog, `readyToInstall` → flush-launch-exit, `error` → pop progress dialog + error snackbar (app stays open). |
| `widgets/update_download_dialog.dart` (new) | The blocking progress dialog (`PopScope(canPop: false)`, themed, indeterminate spinner). |
| Quit seam | The `exit(0)` call sits behind an injectable hook so tests can assert "would have exited" without killing the test runner. |

`updat`'s `closeOnInstall` is deliberately **not** used: it calls `exit(0)`
immediately after launching the installer, which would skip the tab flush.

## Error handling

- **Download fails** → progress dialog closes, `showAppSnackBar` "Couldn't
  download the update.", app stays open (a re-check from Settings re-prompts).
- **Installer launch fails after a good download** → snackbar including the
  downloaded file path so the user can run it manually; **no exit**.
- **Browser fails on macOS** → unchanged existing fallback message.

## Testing

- Widget tests: UPDATE NOW with `installsInApp` true shows the ConfirmDialog;
  cancel keeps the update dialog and downloads nothing; confirm pops both and
  invokes `startUpdate`. Flag false → browser path unchanged. Note text per
  flag. Progress dialog renders and is not dismissible.
- Gate orchestration tests via the injectable exit seam: ready-to-install
  triggers flush → launch → exit in order; error path keeps the app open.
- Existing macOS-path tests stay green.

## Docs & wiki (sync mandate)

- Wiki Auto-Update page: new confirm box, Windows/Linux in-app download +
  auto-open + auto-close, macOS unchanged. Verbatim UI labels.
- `docs/architecture/settings-history-updates.md`: auto-update section
  rewritten to describe the per-platform split.

## Out of scope

- macOS in-app download (blocked on code-signing/notarization).
- Download progress percentage or cancellation (would require Approach B).
- Signing the app.

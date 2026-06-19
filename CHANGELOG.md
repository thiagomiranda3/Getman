# Changelog

All notable changes to **Getman** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] - 2026-06-19

### Fixed

- **Paste cURL on Windows and the web** — pasting a multi-line `curl` command
  (one that uses `\` line continuations) into the URL bar now fills in the
  method, headers, and body on every platform. Previously only the URL was
  populated on Windows and the web build: the single-line URL field collapses
  the pasted newlines to spaces, and the parser mistook each collapsed `\`
  continuation for an escaped space and dropped the flags that followed. The
  parser now treats a collapsed continuation the same as a real newline.

## [1.4.0] - 2026-06-18

### Added

- **Automatic updates** — Getman now checks GitHub for a newer release on
  startup and offers **Update now**, **Skip this version**, or **Later**. A
  toggle and a **CHECK FOR UPDATES** button live in **Settings → General**.
  Updates install from per-platform packages: a `.dmg` on macOS, an Inno Setup
  `.exe` on Windows, and an `AppImage` on Linux.

### Fixed

- **Auto-update reliability** — the detected version and changelog are no longer
  cleared by intermediate progress updates; download failures now surface an
  error instead of failing silently; and the update prompt reliably reads the
  latest release version (timing fix).
- **macOS: keep the App Sandbox enabled** — the updater now launches the
  downloaded installer through `NSWorkspace` (sandbox-safe) and then quits,
  instead of disabling the sandbox. Disabling it had relocated the app's data
  directory (making saved collections/history/environments look lost) and broke
  file import/export; with the sandbox restored, your data and file dialogs work
  as before and updates still install.

## [1.0.0] - 2026-06-15

First stable release. Getman is a high-performance, local-only HTTP client built
with Flutter, featuring a Neo-Brutalist design and a tabbed, keyboard-driven
workflow. Runs on macOS, Windows, and Linux.

### Requests

- **Tabbed request UI** — multiple concurrent requests, each with its own state,
  response cache, and in-flight cancellation.
- **Common HTTP methods** — GET, POST, PUT, DELETE, PATCH.
- **URL bar** with live query-parameter editing and `{{variable}}` highlighting.
- **Body types** — none, raw, `x-www-form-urlencoded`, `multipart/form-data`
  (with file uploads), and binary.
- **Headers & params editors** with reusable key/value rows.
- **JSON syntax highlighting** in both the request body and the response, plus
  one-key **beautify/prettify** (Cmd/Ctrl+B).
- **Paste a cURL command** into the URL bar to populate method, URL, headers,
  and body automatically.
- **Request cancellation** mid-flight.

### Authentication

- **None, inherit, Bearer token, Basic, and API-key** auth, applied at send time.

### Response viewer

- **Body** (pretty/raw toggle), **headers**, **cookies**, **tests**, and
  **metadata** (status code, elapsed time, size) tabs.
- **Large-response handling** — a fast plain-text viewer for big payloads, with
  an optional "always prettify large responses" setting.
- **Copy** and **save-to-file** (`.json` / `.txt`) for the verbatim response body.

### Collections

- **Tree of folders and requests** with drag-and-drop reordering and moving.
- **Favorites** and deterministic sorting (favorites → folders → leaves,
  alphabetical).
- **Free-text descriptions** on folders and requests.
- **Saved examples** — capture request+response snapshots on a request and reopen
  them as read-only tabs.
- **Postman v2.1 import/export** for collections (including `multipart` and
  `urlencoded` form bodies).
- **Git-friendly workspace mirror** for version-controlling collections.

### Environments & variables

- **Multiple environments** with `{{variable}}` substitution across URL, query
  values, header values, and body.
- **Active-environment selector** (with a "No Environment" option).
- **Dynamic variables** resolved at send time — `{{$guid}}` / `{{$randomUUID}}`,
  `{{$timestamp}}`, `{{$isoTimestamp}}`, `{{$randomInt}}`.
- **Secret/masked variables** — per-variable lock with a reveal toggle; masked on
  export.
- **Variable highlighting** distinguishing resolved vs. unresolved tokens.

### Chaining (no-code)

- **Post-response assertions** to validate status, headers, and body.
- **Variable extraction** that writes captured values back into the active
  environment after a send.

### History

- **Automatic request history** (newest-first), de-duplicated by method + URL +
  body, with a configurable size limit. History stores the templated (unresolved)
  request so it can be re-sent under any environment.

### Cookies

- **Cookie jar** persisted locally, applied automatically on the live client.
- **Cookie manager** to inspect and delete individual cookies by domain.

### Realtime

- **WebSocket** connections.
- **Server-Sent Events (SSE)** streaming.

### Code generation

- Export any request as **cURL**, **JavaScript fetch**, **Node axios**,
  **Python requests**, **Go net/http**, or **Java OkHttp**.

### Networking

- **Configurable max-redirects** limit.
- **Client-certificate (mTLS)** support via PEM cert/key + passphrase.

### Productivity & theming

- **Command palette** (Cmd/Ctrl+K) for fuzzy-jumping to a saved request,
  environment, or theme.
- **Three themes** — Brutalist, Editorial, and RPG ("Arcane Quest") — each with
  light/dark and compact modes.
- **Responsive layouts** — split-pane on desktop, unified panel on narrow widths.
- **Keyboard shortcuts** — new tab (Cmd/Ctrl+N), close tab (+W), save (+S), send
  (+Enter), beautify (+B), command palette (+K), focus URL (+L), next/prev tab
  (Ctrl+Tab / Ctrl+Shift+Tab), and jump-to-tab (Cmd/Ctrl+1–9).

### Persistence & platforms

- **Local-only persistence** (Hive) — no account, no cloud, nothing leaves the
  machine.
- Ships for **macOS**, **Windows**, and **Linux** desktop.

[1.0.0]: https://github.com/thiagomiranda3/Getman/releases/tag/1.0.0

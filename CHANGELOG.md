# Changelog

All notable changes to **Getman** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.0] - 2026-07-16

### Added

- **Git-native collaboration for collections** (desktop) — work with your API
  collections through real git: no account, no cloud workspace. Builds on the
  git-friendly workspace mirror, and Getman never stores a credential or edits
  your global git config. Four parts:
  - **Review & commit** — a **REVIEW CHANGES** dialog in the collections header
    lists every changed request/folder with a field-level *semantic* diff
    (method, URL, headers, body, auth — secret values are never printed),
    per-node stage checkboxes, a commit-message box, and inline error
    surfacing. Commits use a Getman-owned identity you configure in settings.
  - **Branch & sync** — a branch chip shows the current branch with
    ahead/behind counts and a menu to switch or create branches,
    **PULL (REBASE)**, **PUSH** (sets the upstream on a first push), and manage
    stashes (list / pop / drop). Switching with uncommitted changes prompts to
    review or stash first, and the tree reloads automatically after git
    changes the disk.
  - **Pull requests** — via the GitHub CLI (`gh`): list the repo's open PRs
    (draft tag + CI check status, tap to open in the browser) and create one
    from the current branch — the branch is pushed first, so a never-pushed
    branch opens a PR in one step. Auth rides entirely on your existing
    `gh` login.
  - **Conflict resolution & auto-fetch** — a pull that hits conflicts opens a
    field-by-field resolver instead of bouncing you to the command line.
    Fields only one side changed merge automatically; for true overlaps pick
    **Take Incoming** / **Keep Yours** (with inline edit for text fields),
    then **RESOLVE & CONTINUE** — or cancel to restore the exact pre-pull
    state. A background fetch (~5 min) keeps the ahead/behind counts fresh
    without ever touching your collections.

### Fixed

An app-wide hardening pass — roughly 75 small, surgical fixes, each with a
regression test. Highlights:

- **Networking & cookies** — the redirect loop now captures each hop's
  `Set-Cookie` (a login 302's cookie is re-sent on the next hop), applies
  RFC 6265 host-only semantics, strips `Authorization` when a redirect crosses
  hosts, and follows 301/302/303 vs 307/308 method semantics correctly.
  `Set-Cookie` domains that don't cover the request host are rejected.
  Response charset handling fixed, and the HTTP adapter is only rebuilt when
  an adapter-relevant setting actually changed.
- **Realtime** — SSE connections now honor the network settings (verify SSL /
  proxy / mTLS) and the cookie jar, and a non-2xx connect surfaces as an
  `HTTP <code>` error frame instead of silently streaming the error body. The
  Connecting/Streaming frame reaches late subscribers, and connect buttons
  resolve `{{variables}}` at press time.
- **Tabs & panels** — bulk close (Close Others / Close to the Right) cancels
  in-flight sends and prompts for dirty tabs; URL/method edits no longer
  revert newer config edits; response time-travel keeps the newest entry's
  full body; chaining write-back works from tabs in non-active panels; the
  PARAMS/HEADERS/BODY section selection is global across tabs.
- **Collections & workspace** — a failed workspace read is never treated as an
  empty workspace (no more wiping collections on a transient read error);
  app-only data (saved examples, favorites) survives workspace disk reloads;
  request kind and node descriptions persist in the mirror; drag-and-drop and
  tree mutations hardened; git sync autostashes conflicts correctly.
- **Import / export / code generation / cURL** — Postman import/export
  round-trips auth, descriptions, and secret flags without double-encoding
  query params; OpenAPI and API-docs exports fixed (including shared
  parameters); generated code escapes URLs, form fields, header keys, and
  binary file paths, and urlencoded bodies are actually form-encoded; the
  cURL parser handles glued short options (`-XPOST`), ANSI-C quoting
  (`$'...'`), `@file` semantics, and TLS flags.
- **Chaining & environments** — assertion/extraction engines handle null
  leaves, regex alternations, and negative ranges; capture write-back is an
  atomic merge so concurrent captures don't clobber each other; the variable
  name grammar accepts spaces and symbols; environments sort alphabetically;
  URL normalization no longer mangles `{{$dynamic}}` tokens.
- **History** — the dedup signature now covers body shape (GraphQL variables,
  binary file path, multipart fields), so distinct sends aren't collapsed
  into one entry.
- **Settings, updates & misc UI** — numeric settings commit on blur/submit;
  failed update checks are surfaced (and releases without notes still
  prompt); JSON Beautify preserves big integers; the command palette keeps
  the arrow-key selection in view; Cmd/Ctrl+N is dead while a dialog is open;
  plus assorted widget fixes.

### Contributors

Thanks to everyone who contributed since v1.8.1:

- [@ThiagoCortez81](https://github.com/ThiagoCortez81) (Thiago Cortez) —
  the git-native collaboration initiative (review & commit, branch & sync,
  pull requests, conflict resolution) and the PR-Agent CI review gate.
- [@thiagomiranda3](https://github.com/thiagomiranda3) (Thiago Miranda) —
  the app-wide bug-hunt hardening pass (~75 fixes).

## [1.8.1] - 2026-07-02

### Fixed

- **Send the request with `Cmd/Ctrl + Enter` from inside the request editor** —
  the shortcut previously did nothing while the body editor held focus (the
  keystroke was captured as a newline) and only worked from elsewhere in the
  app. It now sends the request as expected. Plain `Enter`, `Shift + Enter`, and
  numpad `Enter` still insert newlines in the editor.
- **The app window now remembers its size and position across restarts
  (macOS)** — Getman no longer reopens at the default small size after you
  resize the window; it restores whatever size and position you left it at.
- **Dropping a request onto an item inside an open folder keeps it in that
  folder** — dragging a request onto another request that lives inside a folder
  now places it in that folder (beside the target) instead of incorrectly
  moving it out to the top level. Dropping onto a folder, or onto empty space
  for the root, is unchanged.

## [1.8.0] - 2026-06-26

### Added

- **MCP client support** — connect to **Model Context Protocol** servers over
  HTTP and call their tools right from Getman. Pick **MCP** in the request-kind
  selector, enter the server URL, and press **CONNECT** to list the available
  tools; fill in a tool's arguments — with `{{variable}}` resolution, just like
  requests — and call it to see the JSON-rendered result. The MCP protocol is
  labelled alongside the request in the collections tree.

### Changed

- **Large JSON responses are much more responsive** — the **TREE** view now
  parses lazily and off the UI thread, so opening a big JSON response no longer
  blocks the interface. Variable highlighting in editors does a single pass and
  skips lines with no `{{…}}` tokens, and a response's size is computed once
  instead of on every rebuild.
- **Very large responses stay smooth** — bodies above ~3 MiB now render as fast
  plain text instead of attempting full syntax highlighting, keeping scrolling
  and editing fluid.

### Fixed

- **PDF responses no longer crash on platforms without PDF rendering support** —
  the viewer now detects unsupported platforms up front and shows the "Cannot
  render PDF" fallback instead of throwing.

## [1.7.0] - 2026-06-25

### Added

- **Rich response viewers** — responses are now rendered by content type instead
  of always falling back to raw text:
  - **Images** preview inline.
  - **Video & audio** play in an embedded player.
  - **PDF** renders inline with page navigation.
  - **CSV** displays as a sortable table.
  - **HTML** shows the source with an **open-in-browser** action (source-only on
    the web build).
  - Other **binary** payloads get a dedicated viewer.

  A new **PREVIEW** mode sits alongside **RAW** so you can always drop back to the
  bytes/text. (Media bytes are captured for the live response only — they are not
  written to history.)
- **Export collections as API documentation** — export a collection to
  **OpenAPI 3.0.3** (JSON or YAML) or **Markdown** from the collection node menu.
  The export dialog lets you pick the format and the environment to resolve
  `{{variables}}` against.
- **Active request highlighted in the collections tree** — the request linked to
  the current tab is now highlighted with an accent bar and revealed (its parent
  folders expand) so you can always see where the open request lives.

### Changed

- **Liquid Glass — dialogs now render as a frosted, blurred card**, matching the
  rest of the theme's glass surfaces.

### Fixed

- **Find-in-editor panel** — searching the request body / response is faster, and
  **Enter** now steps to the next match.
- **Keyboard shortcuts use the platform-correct modifier** — ⌘ on macOS, Ctrl
  elsewhere — and **Save (⌘/Ctrl+S)** now works correctly while you're typing in a
  code editor (the editor no longer swallows or misfires the shortcut).
- **AURIS** — corrected the favorite-folder icon color and the request-tab hover
  color.

## [1.6.1] - 2026-06-23

### Added

- **Variable autocomplete & highlighting in more places** — type `{{` to get
  `{{var}}` suggestions, and see resolved/unresolved tokens colored live, in the
  request **body** (including the GraphQL VARIABLES pane), **auth** fields, and
  **form-data** values — matching the existing URL, params, and headers
  behavior.

### Changed

- **Calmer theme motion** — the animated effects have been toned down
  considerably: button presses are now a single subtle effect, and the per-send
  "ritual", the in-flight panel frame, status-code reactions, request/tab
  open-close transitions, and per-click background ripples have been removed.
  The gentle ambient drift, parallax, and idle breathing are kept.
- **The previous response now stays visible while a request re-sends**, instead
  of clearing to a loading state.

### Removed

- **THEME SOUNDS** and **REDUCE VISUAL EFFECTS** settings toggles (and the
  underlying audio subsystem) — the toned-down motion no longer needs them.

### Fixed

- Assorted UI fixes; the code-editor caret and selection now use the theme
  accent color so they stay visible on dark themes such as AURIS.

## [1.4.1] - 2026-06-19

### Fixed

- **macOS: "Update now" no longer produces an app that won't open** — the
  in-app updater used to download the `.dmg` itself, but a file written by the
  sandboxed app is flagged by macOS in a way that makes the dragged-out app get
  blocked as "damaged" on this un-notarized build (the download was never
  actually corrupted — it is byte-identical to the release). **Update now** now
  opens the download in your default browser instead, which installs cleanly.
  As before, on first launch allow it via right-click → Open.
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

[1.8.0]: https://github.com/thiagomiranda3/Getman/releases/tag/v1.8.0
[1.7.0]: https://github.com/thiagomiranda3/Getman/releases/tag/v1.7.0
[1.0.0]: https://github.com/thiagomiranda3/Getman/releases/tag/1.0.0

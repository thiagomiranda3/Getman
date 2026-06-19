<p align="center">
  <img src="assets/brand/icon_1024.png" alt="Getman" width="160" height="160">
</p>

# Getman

A fast, native HTTP client for desktop and the web — built with Flutter,
wrapped in six visual themes that **react to your requests** with motion and
optional sound.

**Live demo:** https://thiagomiranda3.github.io/Getman/
**Download:** [latest release for macOS, Windows, Linux](https://github.com/thiagomiranda3/Getman/releases/latest)
**Full feature docs:** [the wiki](https://github.com/thiagomiranda3/Getman/wiki)

---

## Why Getman?

Most HTTP clients are either browser tabs pretending to be apps (Electron +
Chromium, slow cold starts, 200 MB RAM to show a textbox) or subscription
products that want an account before you can save a request. Getman is the
opposite: a native binary under 25 MB, no account, no cloud sync, no
telemetry, and everything you do is persisted locally in a Hive database on
your machine. Open it, send a request, close it — same as `curl`, but with
tabs, history, and a proper JSON viewer.

It also doesn't look like every other dev tool. Ships six full themes: the
calm, native-style **Classic** (the default); **Brutalist** (thick borders,
hard shadows, uppercase type); **Editorial** (a quieter, long-form reading
aesthetic); **Arcane Quest** (a tongue-in-cheek fantasy RPG skin); **Dracula**
(the popular dark palette); and **Liquid Glass** (Apple-inspired frosted-glass
panels with real backdrop blur). Pick one from the settings dialog — they all
share the same engine. And they're not static: each theme **reacts to what you
do** — a flourish on a `200`, a different effect on a `500`, a themed send
ritual, animated backgrounds, and optional sound cues.

## Features

- **Tabbed request workspace.** Every request is a tab with its own
  method, URL, headers, params, body, and response. Tabs persist across
  restarts (debounced saves, no surprise data loss).
- **Tab panels (virtual desktops).** Group tabs into named panels and switch
  between them like virtual desktops for your requests — move tabs between
  panels, reorder, and jump with the keyboard.
- **Collections tree** with drag-and-drop reordering, folders, favorites,
  rename/delete, free-text descriptions per folder or request, per-node
  "save" to snapshot the current tab, and **saved examples** — capture a
  request+response pair on a node and reopen it later as an unlinked tab.
- **Request history** with automatic dedup by method + URL + body, a
  configurable size limit, and newest-first ordering.
- **Environments & variables.** Define named variable sets (`API_HOST`,
  `TOKEN`, …) and reference them anywhere — URL, query params, headers, or
  body — with `{{var}}` syntax. The URL bar highlights each token live (green
  for resolved, red for unknown), and the active environment is one click away
  in the top bar. Flag any variable as **secret** to mask + redact it. Built-in
  **dynamic variables** (`{{$guid}}`, `{{$timestamp}}`, `{{$randomInt}}`, …)
  resolve at send time, and **collection-scoped variables** let a folder define
  vars its requests inherit (the active environment wins on conflict).
- **Postman import / export.** Bring your existing `.json` collections in,
  or export Getman collections to share with teammates who still use
  Postman.
- **cURL paste.** Paste a `curl https://…` command into the URL bar and
  Getman parses it into method, URL, headers, and body in one step.
- **Authentication.** Bearer, Basic, and API-key (header or query) auth,
  resolved with `{{variables}}` at send time, inheritable from a parent folder.
- **Request bodies.** Raw, `x-www-form-urlencoded`, `multipart/form-data`
  with file uploads, and binary.
- **Code generation.** Export any request as cURL, JavaScript `fetch`,
  Node.js `axios`, Python `requests`, Go `net/http`, or Java OkHttp —
  `{{variables}}` left intact.
- **No-code tests & chaining.** Capture a value from one response (JSONPath,
  header, or regex) into an environment variable, and assert on status,
  time, body, or headers — all without writing a script.
- **Rich response viewer.** Pretty / raw / **collapsible JSON tree** (copy a
  value, copy its JSONPath, or one-click **extract to `{{var}}`**), plus
  headers, cookies, and test results. **Per-tab response time-travel** keeps
  recent responses so you can step back through them, and a **compare/diff**
  view shows exactly what changed between two responses. Copy the body or save
  it to a file.
- **Persistent cookie jar.** Per-domain cookies are sent automatically on
  later requests, so session-based auth just works — with a manager dialog
  to inspect and delete individual cookies (grouped by domain).
- **Git-friendly workspace (desktop).** Mirror collections to a folder of
  readable JSON files you can commit and review in PRs.
- **Command palette.** `Cmd/Ctrl+K` to fuzzy-jump to any saved request,
  environment, theme, or recent history entry — and `Cmd/Ctrl+E` to switch
  environment directly.
- **Realtime.** WebSocket and Server-Sent Events with a live message log.
- **Configurable networking.** Timeouts, follow-redirects (with a
  max-redirects cap), SSL verification, HTTP proxy, and **client-certificate
  (mTLS)** — all in Settings.
- **JSON editor, not a textarea.** Request and response bodies use
  `re_editor` with syntax highlighting, a built-in find panel, and a
  one-keystroke beautifier (Ctrl/Cmd+B).
- **Cancel in-flight requests.** Long-running call? Hit cancel — the Dio
  client is torn down cleanly and no stale response arrives five minutes
  later.
- **Six reactive themes.** Classic (the calm default), Brutalist, Editorial,
  Arcane Quest, Dracula, and Liquid Glass — swap live without a restart. The
  themes **react to your requests**: a success flourish, a distinct error
  effect, a themed send ritual, animated backgrounds, and optional sound cues.
  Compact mode tightens spacing; **Reduce Visual Effects** turns the motion off.
- **Auto-update (desktop).** Checks GitHub for a newer release on startup and
  offers to update; toggle it off in Settings.
- **Keyboard-driven.** Send, save, beautify, open/close/switch tabs, manage
  panels, switch environment, and jump to the URL bar — all without leaving
  the home row.
- **Local-first, private.** No accounts, no cloud, no telemetry. All data
  lives in a Hive store in your app-data directory.

## Install

| Platform    | Download                                                                                           |
|-------------|----------------------------------------------------------------------------------------------------|
| macOS       | `getman-vX.Y.Z-macos-arm64.dmg` — open it, drag `Getman.app` into `/Applications`                  |
| Windows     | `getman-vX.Y.Z-windows-x64-setup.exe` — run the Inno Setup installer                               |
| Linux (x64) | `getman-vX.Y.Z-linux-x86_64.AppImage` — `chmod +x getman-*.AppImage && ./getman-*.AppImage`        |
| Web         | [Open the live demo](https://thiagomiranda3.github.io/Getman/) (CORS applies — see note below)     |

Grab them from the [Releases page](https://github.com/thiagomiranda3/Getman/releases/latest).

The first time you open the macOS or Windows build you'll see an
"unidentified developer" / SmartScreen warning — the releases aren't
code-signed yet. On macOS: right-click the app → Open, then confirm. On
Windows: click "More info" → "Run anyway".

## Keyboard shortcuts

| Action             | macOS                | Windows / Linux       |
|--------------------|----------------------|-----------------------|
| New tab            | `Cmd + N`            | `Ctrl + N`            |
| Close current tab  | `Cmd + W`            | `Ctrl + W`            |
| Send request       | `Cmd + Enter`        | `Ctrl + Enter`        |
| Save to collection | `Cmd + S`            | `Ctrl + S`            |
| Beautify JSON body | `Cmd + B`            | `Ctrl + B`            |
| Command palette    | `Cmd + K`            | `Ctrl + K`            |
| Switch environment | `Cmd + E`            | `Ctrl + E`            |
| Focus URL bar      | `Cmd + L`            | `Ctrl + L`            |
| Next / previous tab| `Ctrl + Tab` / `+Shift` | `Ctrl + Tab` / `+Shift` |
| Jump to tab 1–9    | `Cmd + 1…9`          | `Ctrl + 1…9`          |
| New panel          | `Cmd + Shift + N`    | `Ctrl + Shift + N`    |
| Next / previous panel | `Cmd + Shift + ]` / `[` | `Ctrl + Shift + ]` / `[` |
| Jump to panel 1–9  | `Cmd + Shift + 1…9`  | `Ctrl + Shift + 1…9`  |

## Running from source

Getman targets Flutter `3.41.6` (pinned via `.fvmrc`). Use
[FVM](https://fvm.app) so your local build matches CI:

```sh
fvm install           # first time only
fvm flutter pub get
fvm flutter run -d macos      # or -d windows / -d linux / -d chrome
```

For full per-platform **release** builds (macOS / Windows / Linux / web),
required toolchains, and build troubleshooting, see
[`docs/BUILD.md`](./docs/BUILD.md).

Generated Hive adapters are committed — no build_runner step needed for a
plain run. After changing any `@HiveType` field:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Before opening a PR:

```sh
fvm flutter analyze                    # very_good_analysis — 0 issues
fvm dart run custom_lint               # Getman architecture rules
fvm dart run bloc_tools:bloc lint lib  # bloc_lint
fvm dart format lib test tools         # formatter (the commit hook enforces it)
fvm flutter test                       # must be 100% green
```

The `.githooks/pre-commit` hook runs the analysis + format gate automatically —
enable it once per clone with `git config core.hooksPath .githooks`.

Project layout, architectural rules, and feature-level invariants live in
[`CLAUDE.md`](./CLAUDE.md) — worth reading before your first non-trivial
change.

## Releasing

Releases are built and published by `.github/workflows/release.yml` on
every pushed tag that matches `v*.*.*`. The workflow produces one artifact
per platform and attaches them all to a GitHub Release that is **published
automatically**, using the matching section of `CHANGELOG.md` as the release
notes (with GitHub's auto-generated commit/PR notes appended).

### Cut a new version

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.1+2`).
2. Add a `## [X.Y.Z]` section to [`CHANGELOG.md`](./CHANGELOG.md) — the
   release job uses it as the release body (tag `vX.Y.Z` → the `[X.Y.Z]`
   heading).
3. Commit and push to `master`.
4. Tag and push:
   ```sh
   git tag v1.0.1
   git push origin v1.0.1
   ```
5. Watch the run in the repo's **Actions** tab. When all four build jobs
   finish, the release is **published automatically** under **Releases**
   with all four artifacts attached.

### Test the workflow without cutting a release

Trigger it manually via **Actions → Release → Run workflow** and supply a
tag label (e.g. `v0.0.0-dev`). Manual runs build all four platforms and
upload artifacts to the run summary, but **skip** the release-publishing
step.

## Web deploy (GitHub Pages)

The `master` branch auto-deploys to GitHub Pages via
`.github/workflows/pages.yml`. The workflow builds with
`--base-href=/Getman/` (matching the Pages subpath), adds `.nojekyll` +
`404.html`, and publishes via the official `actions/deploy-pages`.

### One-time setup (repo owner)

1. **Settings → Pages → Build and deployment → Source:** select
   **GitHub Actions**. (This is a one-time click — without it, the
   `deploy-pages` step fails with "Not Found".)
2. Merge/push the workflow to `master`. The first run publishes the site.
3. (Optional) Enable **Settings → Environments → github-pages → Required
   reviewers** if you want manual approval before each deploy.

### If you rename the repo

Update `BASE_HREF` in `.github/workflows/pages.yml` to match the new
subpath (e.g. `/new-name/`). Pages URLs are case-sensitive — the value
must exactly match the repo name's casing.

### Caveats for the web build

- **CORS.** Browsers block cross-origin requests without the right
  response headers, so many APIs will fail from the hosted demo even
  though they'd work from the desktop app. Not a bug — a browser
  security model difference.
- **Persistence.** Hive on web uses IndexedDB, scoped to the origin.
  Collections/history/tabs survive refresh but are per-browser.
- **Realtime.** WebSocket works on web, but the browser can't set custom
  headers on the handshake (use a query param or subprotocol for auth). SSE
  may buffer instead of streaming incrementally under the browser HTTP
  adapter — it streams as expected on the desktop builds.
- **Workspace folders & network config** (timeouts/SSL/proxy) are
  desktop/mobile features; the browser manages these itself.

## Release limitations

- **Unsigned builds.** macOS shows "unidentified developer"; Windows
  shows SmartScreen warnings. Users can bypass, but signing +
  notarization is the next upgrade (Apple Developer cert for macOS, EV
  cert or Azure Trusted Signing for Windows).
- **Apple Silicon only** on macOS. `macos-latest` runners are arm64. To
  also ship Intel, add a second job on `macos-13` or build a universal
  binary.
- **x86\_64 only** on Linux. Add an arm64 runner if you need Linux-arm.
- **Auto-update is browser-assisted on macOS.** The app detects new releases
  on startup and prompts, but because builds are unsigned, "Update now" on
  macOS opens the release asset in your browser to download manually (a
  quarantined unsigned `.dmg` would otherwise be flagged "damaged") rather than
  installing in place. Code signing would let it update fully in-app.

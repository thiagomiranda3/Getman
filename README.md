<p align="center">
  <img src="assets/brand/icon_1024.png" alt="Getman" width="160" height="160">
</p>

# Getman

A fast, native HTTP client for desktop and the web — built with Flutter,
wrapped in a choice of three deliberately opinionated visual themes.

**Live demo:** https://thiagomiranda3.github.io/Getman/
**Download:** [latest release for macOS, Windows, Linux](https://github.com/thiagomiranda3/Getman/releases/latest)

---

## Why Getman?

Most HTTP clients are either browser tabs pretending to be apps (Electron +
Chromium, slow cold starts, 200 MB RAM to show a textbox) or subscription
products that want an account before you can save a request. Getman is the
opposite: a native binary under 25 MB, no account, no cloud sync, no
telemetry, and everything you do is persisted locally in a Hive database on
your machine. Open it, send a request, close it — same as `curl`, but with
tabs, history, and a proper JSON viewer.

It also doesn't look like every other dev tool. The default **Brutalist**
theme leans hard into thick borders, hard shadows, and uppercase display
type; **Editorial** is a quieter, long-form reading aesthetic; **Arcane
Quest** is a tongue-in-cheek fantasy RPG skin. Pick one from the settings
dialog — they all share the same engine.

## Features

- **Tabbed request workspace.** Every request is a tab with its own
  method, URL, headers, params, body, and response. Tabs persist across
  restarts (debounced saves, no surprise data loss).
- **Collections tree** with drag-and-drop reordering, folders, favorites,
  rename/delete, and per-node "save" to snapshot the current tab's
  request.
- **Request history** with automatic dedup by method + URL + body, a
  configurable size limit, and newest-first ordering.
- **Environments.** Define named variable sets (`API_HOST`, `TOKEN`, …) and
  reference them anywhere — URL, query params, headers, or body — with
  `{{var}}` syntax. The URL bar highlights each token live (green for
  resolved, red for unknown). The active environment is one click away in
  the top bar.
- **Postman import / export.** Bring your existing `.json` collections in,
  or export Getman collections to share with teammates who still use
  Postman.
- **cURL paste.** Paste a `curl https://…` command into the URL bar and
  Getman parses it into method, URL, headers, and body in one step.
- **JSON editor, not a textarea.** Request and response bodies use
  `re_editor` with syntax highlighting, a built-in find panel, and a
  one-keystroke beautifier (Ctrl/Cmd+B).
- **Cancel in-flight requests.** Long-running call? Hit cancel — the Dio
  client is torn down cleanly and no stale response arrives five minutes
  later.
- **Three themes.** Brutalist, Editorial, Arcane Quest — swap live without
  a restart. Compact mode tightens spacing on smaller displays.
- **Keyboard-driven.** Send, save, beautify, close, and open tabs without
  leaving the home row.
- **Local-first, private.** No accounts, no cloud, no telemetry. All data
  lives in a Hive store in your app-data directory.

## Install

| Platform    | Download                                                                                           |
|-------------|----------------------------------------------------------------------------------------------------|
| macOS       | `getman-vX.Y.Z-macos-arm64.zip` — unzip, drag `Getman.app` into `/Applications`                    |
| Windows     | `getman-vX.Y.Z-windows-x64.zip` — unzip anywhere, run `getman.exe`                                 |
| Linux (x64) | `getman-vX.Y.Z-linux-x64.tar.gz` — `tar -xzf … && ./getman`                                        |
| Web         | [Open the live demo](https://thiagomiranda3.github.io/Getman/) (CORS applies — see note below)     |

Grab them from the [Releases page](https://github.com/thiagomiranda3/Getman/releases/latest).

The first time you open the macOS or Windows build you'll see an
"unidentified developer" / SmartScreen warning — the releases aren't
code-signed yet. On macOS: right-click the app → Open, then confirm. On
Windows: click "More info" → "Run anyway".

## Keyboard shortcuts

| Action             | macOS          | Windows / Linux |
|--------------------|----------------|-----------------|
| New tab            | `Cmd + N`      | `Ctrl + N`      |
| Close current tab  | `Cmd + W`      | `Ctrl + W`      |
| Send request       | `Cmd + Enter`  | `Ctrl + Enter`  |
| Save to collection | `Cmd + S`      | `Ctrl + S`      |
| Beautify JSON body | `Cmd + B`      | `Ctrl + B`      |

## Running from source

Getman targets Flutter `3.41.6` (pinned via `.fvmrc`). Use
[FVM](https://fvm.app) so your local build matches CI:

```sh
fvm install           # first time only
fvm flutter pub get
fvm flutter run -d macos      # or -d windows / -d linux / -d chrome
```

Generated Hive adapters are committed — no build_runner step needed for a
plain run. After changing any `@HiveType` field:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Before opening a PR:

```sh
fvm flutter analyze        # must report: No issues found!
fvm flutter test           # must be 100% green
```

Project layout, architectural rules, and feature-level invariants live in
[`CLAUDE.md`](./CLAUDE.md) — worth reading before your first non-trivial
change.

## Releasing

Releases are built and published by `.github/workflows/release.yml` on
every pushed tag that matches `v*.*.*`. The workflow produces one artifact
per platform and attaches them all to a **draft** GitHub Release, which
you review and publish manually.

### Cut a new version

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.1+2`).
2. Commit and push to `master`.
3. Tag and push:
   ```sh
   git tag v1.0.1
   git push origin v1.0.1
   ```
4. Watch the run in the repo's **Actions** tab. When all four build jobs
   finish, a draft release appears under **Releases** — review the
   auto-generated notes and hit **Publish**.

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

## Release limitations

- **Unsigned builds.** macOS shows "unidentified developer"; Windows
  shows SmartScreen warnings. Users can bypass, but signing +
  notarization is the next upgrade (Apple Developer cert for macOS, EV
  cert or Azure Trusted Signing for Windows).
- **Apple Silicon only** on macOS. `macos-latest` runners are arm64. To
  also ship Intel, add a second job on `macos-13` or build a universal
  binary.
- **x86\_64 only** on Linux. Add an arm64 runner if you need Linux-arm.
- **No auto-update.** Users re-download from Releases. Adding an updater
  (e.g. Sparkle on macOS, `auto_updater` package cross-platform) is a
  separate project.

# getman

A fast an nice http program

**Live demo:** https://thiagomiranda3.github.io/Getman/ (auto-deployed from `master`)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Releasing

Releases are built and published by `.github/workflows/release.yml` on every
pushed tag that matches `v*.*.*`. The workflow produces one artifact per
platform and attaches them all to a **draft** GitHub Release, which you review
and publish manually.

### Cut a new version

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.1+2`).
2. Commit and push to `master`.
3. Tag and push:
   ```sh
   git tag v1.0.1
   git push origin v1.0.1
   ```
4. Watch the run in the repo's **Actions** tab. When all four build jobs finish,
   a draft release appears under **Releases** — review the auto-generated notes
   and hit **Publish**.

### Artifacts

| Platform | File                               | Contents                    |
|----------|------------------------------------|-----------------------------|
| macOS    | `getman-vX.Y.Z-macos-arm64.zip`    | `getman.app` (Apple Silicon)|
| Windows  | `getman-vX.Y.Z-windows-x64.zip`    | `getman.exe` + runtime DLLs |
| Linux    | `getman-vX.Y.Z-linux-x64.tar.gz`   | `getman` + `data/` + `lib/` |
| Web      | `getman-vX.Y.Z-web.zip`            | Contents of `build/web/`    |

### Test the workflow without cutting a release

Trigger it manually via **Actions → Release → Run workflow** and supply a tag
label (e.g. `v0.0.0-dev`). Manual runs build all four platforms and upload
artifacts to the run summary, but **skip** the release-publishing step.

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
subpath (e.g. `/new-name/`). Pages URLs are case-sensitive — the value must
exactly match the repo name's casing.

### Caveats for the web build

- **CORS.** Browsers block cross-origin requests without the right
  response headers, so many APIs will fail from the hosted demo even
  though they'd work from the desktop app. Not a bug — a browser
  security model difference.
- **Persistence.** Hive on web uses IndexedDB, scoped to the origin.
  Collections/history/tabs survive refresh but are per-browser.

## Release limitations

- **Unsigned builds.** macOS shows "unidentified developer"; Windows shows
  SmartScreen warnings. Users can bypass, but signing + notarization is the
  next upgrade (Apple Developer cert for macOS, EV cert or Azure Trusted
  Signing for Windows).
- **Apple Silicon only** on macOS. `macos-latest` runners are arm64. To also
  ship Intel, add a second job on `macos-13` or build a universal binary.
- **x86\_64 only** on Linux. Add an arm64 runner if you need Linux-arm.
- **No auto-update.** Users re-download from Releases. Adding an updater
  (e.g. Sparkle on macOS, `auto_updater` package cross-platform) is a
  separate project.

# Building Getman

This is the full reference for building Getman from source — toolchain setup,
per-platform release builds, and troubleshooting. For a quick dev-run and the
contribution checklist, the [README "Running from source"](../README.md#running-from-source)
section is enough; come here when you need to produce distributable binaries
or set up a fresh machine.

> **TL;DR**
> ```sh
> fvm install                       # pull the pinned Flutter (first time)
> fvm flutter pub get               # fetch dependencies
> fvm flutter run -d macos          # dev run (or -d windows / -d linux / -d chrome)
> fvm flutter build macos --release # release binary for the current OS
> ```

---

## 1. Prerequisites

### Flutter (via FVM)

Getman pins **Flutter `3.44.4`** in [`.fvmrc`](../.fvmrc). Use
[FVM](https://fvm.app) so your local toolchain matches CI exactly — a
different Flutter version can produce different output or fail codegen.

```sh
dart pub global activate fvm   # or: brew install fvm  (macOS)
fvm install                    # installs the pinned 3.44.4 into this repo
```

Every `flutter` / `dart` command below is prefixed with `fvm` so it runs
against the pinned SDK. (Plain `flutter ...` uses whatever is on your `PATH`
and is **not** supported here.)

### Platform toolchains

You can only build the binary for the OS you are currently on (see
[§4 Cross-compilation](#4-cross-compilation)). Install the toolchain for each
target you actually build:

| Target  | What you need |
|---------|---------------|
| **macOS**   | Xcode (full install, not just CLT) + an accepted license, then `xcodebuild -runFirstLaunch`. CocoaPods (`sudo gem install cocoapods` or `brew install cocoapods`). |
| **Windows** | Visual Studio 2022 with the **"Desktop development with C++"** workload (MSVC toolchain, Windows 10/11 SDK, CMake). |
| **Linux**   | `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev` — on Debian/Ubuntu: `sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`. |
| **Web**     | A Chromium-based browser for `-d chrome`. Nothing extra to build the bundle. |

Run `fvm flutter doctor` to confirm a target is fully set up — it lists
exactly what's missing per platform.

---

## 2. First-time setup

```sh
git clone https://github.com/thiagomiranda3/Getman
cd Getman
fvm install                # first time only
fvm flutter pub get
```

### Code generation (Hive adapters)

The generated `*.g.dart` Hive adapters **are committed**, so a clean checkout
builds and runs with no codegen step. You only need to regenerate after
changing an `@HiveType` / `@HiveField` (see the typeId table in
[`CLAUDE.md`](../CLAUDE.md#3-domain-model-hive-typeids-are-load-bearing)):

```sh
dart run build_runner build --delete-conflicting-outputs
```

---

## 3. Building

### Run in development

```sh
fvm flutter run -d macos       # macOS desktop
fvm flutter run -d windows     # Windows desktop
fvm flutter run -d linux       # Linux desktop
fvm flutter run -d chrome      # web (Chrome)
```

Use `fvm flutter devices` to list what's available on your machine.

### Release builds

Each command below builds an optimized release binary **for the OS you run it
on**. Output locations match what the release workflow packages.

#### macOS

```sh
fvm flutter build macos --release
```

- **Output:** `build/macos/Build/Products/Release/getman.app`
- **Distribute:** zip the `.app` preserving symlinks (this is exactly what CI
  does):
  ```sh
  ditto -c -k --sequesterRsrc --keepParent \
    build/macos/Build/Products/Release/getman.app getman-macos.zip
  ```
- Builds for the host architecture — `macos-latest`/Apple Silicon produces an
  **arm64** app. The binary is **unsigned**; see [§6](#6-signing--notarization).

#### Windows

```sh
fvm flutter build windows --release
```

- **Output:** `build\windows\x64\runner\Release\` — `getman.exe` plus its DLLs
  and a `data\` folder.
- **Distribute:** ship the **entire `Release\` folder** (the exe alone won't
  run). Zip it:
  ```powershell
  Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath getman-windows.zip
  ```

#### Linux

```sh
fvm flutter build linux --release
```

- **Output:** `build/linux/x64/release/bundle/` — the `getman` executable plus
  `lib/` and `data/`.
- **Distribute:** archive the **whole `bundle/` directory**:
  ```sh
  tar -czf getman-linux.tar.gz -C build/linux/x64/release/bundle .
  ```
- Builds x86_64. For arm64 you need an arm64 Linux host.

#### Web

```sh
fvm flutter build web --release
```

- **Output:** `build/web/` — static files; serve from any static host.
- For a sub-path deploy (e.g. GitHub Pages) pass
  `--base-href "/Getman/"`. See the README's
  [Web deploy](../README.md#web-deploy-github-pages) section.

---

## 4. Cross-compilation

**You cannot build Windows or Linux binaries from macOS (or any other
cross-combination).** Flutter desktop builds are host-locked — the build needs
that OS's native toolchain (Xcode, MSVC, GTK). There is no `--target-os` flag.

To produce all platforms at once, **let CI do it**: push a `v*.*.*` tag and
the [release workflow](../.github/workflows/release.yml) builds macOS,
Windows, Linux, and web on their respective GitHub-hosted runners and attaches
the artifacts to a published GitHub Release. The full release procedure is in
the README's [Releasing](../README.md#releasing) section.

---

## 5. Verifying a build

Before opening a PR or cutting a release, the bar is:

```sh
fvm flutter analyze        # must report: No issues found!
fvm flutter test           # must be 100% green
```

> `analyze` alone can occasionally false-pass on generic-variance issues that
> the real compiler rejects. For changes that affect compilation, trust a real
> build — `fvm flutter test` (runs the CFE) or `fvm flutter build macos
> --debug` — over `analyze` alone.

---

## 6. Signing & notarization

Release binaries are currently **unsigned**:

- **macOS** — first launch shows "unidentified developer". Right-click the app
  → **Open** → confirm (or `xattr -dr com.apple.quarantine Getman.app`).
  Proper fix: an Apple Developer ID certificate + notarization.
- **Windows** — SmartScreen warns on first run. Click **More info → Run
  anyway**. Proper fix: an EV code-signing cert or Azure Trusted Signing.

These are deliberate omissions (certs cost money); they don't affect the build
itself.

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `flutter` uses the wrong version | Prefix every command with `fvm`. Re-run `fvm install`; check `fvm list`. |
| `build_runner` "conflicting outputs" | `dart run build_runner build --delete-conflicting-outputs`. |
| macOS: CocoaPods / pod errors | `cd macos && pod repo update && pod install`, then rebuild. |
| macOS: "CommandLineTools" / no Xcode | Install full Xcode, `sudo xcode-select -s /Applications/Xcode.app`, `sudo xcodebuild -runFirstLaunch`. |
| Linux: `CMake … could not find` GTK/etc. | Install the apt deps in [§1](#platform-toolchains); re-run `fvm flutter doctor`. |
| Windows: "Unable to find suitable Visual Studio" | Install VS 2022 **Desktop development with C++** workload. |
| Stale build artifacts / weird errors | `fvm flutter clean && fvm flutter pub get`, then rebuild. |

When in doubt, `fvm flutter doctor -v` pinpoints what's missing for each
target.

# Scripting verification — 2026-10-30

## Scope and reproducibility

Development uses Flutter 3.44.4 / Dart 3.12.2 through FVM on an Apple M3 Max
with 36 GiB RAM, macOS 27.0.1 (26A434), arm64.
The native bridge vendors QuickJS-NG 0.14.0; the browser bundles
quickjs-emscripten 0.31.0. Manifests under `tool/scripting/` record sources,
licenses and SHA-256 hashes. `npm ci --prefix tool/scripting --ignore-scripts`
and `npm run build --prefix tool/scripting` rebuild the browser artifacts.

Domain/runtime/persistence/environment/pipeline/UI increments were tested before
implementation. Review findings were reproduced with regression tests before
fixing: prototype-like input names, source locations, fatal memory failures,
retained diagnostics, nested async tests, intermediate secret assignments,
private envelope serialization, imported-content trust, explicit trust
continuity, cancellation visibility and compact-panel error focus.

The fixtures in `integration_test/fixtures/scripts/` are synthetic. Full-stack
contracts use actual QuickJS, Dio, Hive and a local server; no external API,
credentials or fake engine supplies their results. Native and browser runtime
contracts exercise real interruption and recovery. Native counters check that
controls and runtimes return to zero after error/cancel/close.

## Verified local results

- Full Flutter suite: **3,913 passing tests**, no failures.
- Line coverage: **94.7%** (25,139 / 26,541 instrumented lines).
- Real Chrome runtime/API/snippet corpus: **56 passing tests**.
- macOS app scripting integration: **11 cases passed in a combined run**
  (9 real HTTP/Hive/QuickJS contracts plus desktop editing/results and compact
  error visibility); targeted UI cases also passed separately. The last replay
  completed 9 runtime/pipeline cases before the graphical runner stopped
  progressing and was interrupted. A fully repeatable final GUI run is pending.
- Browser integrationDriver journeys: **2 passing tests**, real production
  dependencies and local HTTP fixtures.
- Web release build: passed with `/Getman/` base href; bundled bootstrap,
  Worker and WASM bytes match the verified source assets.
- macOS arm64 release build: passed; QuickJS framework is present in the app.
  The temporary architecture/deployment override is described below.
- Four independent static gates: zero analyzer, custom_lint, fixture self-test
  and bloc_lint issues. Dart formatting and owned-file whitespace checks clean.
  Upstream vendored C/license bytes retain their original whitespace so their
  recorded source hashes remain reproducible.

These results are local validation, not a completed cross-platform release
matrix. The pre-existing macOS integration aggregator completed **77 distinct
cases across bounded runs** but did not finish: later live-window waits stalled
in collection flows. An interrupted run reports Flutter stream-sink shutdown
errors and a did-not-complete case; it is **not** a green full integration suite.
The scripting-specific cases are reported separately above.

## Platform notes

The browser integration uses the official `integrationDriver`/ChromeDriver
path, a disposable profile and local CORS fixture server. A temporary test index
loads real PDF.js required by the existing pdfx debug plugin; cleanup restores
the product index and terminates the server/driver. The scripting runtime itself
loads only checked-in offline assets. See `integration_test/run_scripts_web.sh`.

This workstation's Xcode reports an outdated CoreSimulator and rejects its
legacy 10.15 deployment target. Native app tests use a temporary xcconfig
setting `MACOSX_DEPLOYMENT_TARGET = 12.0` through `XCODE_XCCONFIG_FILE`; this does
not change the product deployment target or system installation. Flutter builds
and tests must run serially: simultaneous platform builds rewrite shared native
asset and shader outputs and can make unrelated tests fail to load artifacts.

The macOS universal release attempt failed inside Flutter's
`release_unpack_macos` architecture validation: it rejected `arm64 x86_64`
although `lipo -info` listed both slices. A separate host arm64 release build
passed with temporary xcconfig values `ARCHS = arm64`, `ONLY_ACTIVE_ARCH = YES`
and deployment target 12.0. The app is 57.4 MB and contains the signed native
`getman_quickjs.framework`. No project build setting or SDK was changed to
force this result; universal release validation remains pending.

Windows/Linux are not executable on this workstation. The dedicated native
workflow compiles and runs the bridge on their corresponding runners, including
C11/MSVC atomics configuration. Their actual CI results must be checked before
claiming a verified multiplatform release. Existing release workflows remain
unchanged; no product release or deployment was initiated here.

## Runtime performance

`tool/scripting/benchmark.dart` can be compiled with:

```sh
fvm dart build cli --target=tool/scripting/benchmark.dart --output=/tmp/getman-scripts-benchmark
/tmp/getman-scripts-benchmark/bundle/bin/benchmark
```

It measures an empty-script bypass, first script, 30 warmup runs and 500
subsequent executions in the AOT runtime. RSS includes the VM/allocator and is
not the JavaScript heap limit. Native ownership counters complement RSS.
This is **not** a before/after Flutter cold-boot or HTTP latency benchmark;
no claim about a 10% app-wide p95 regression threshold follows from it.

Measured AOT runtime on this workstation (macOS arm64, Dart 3.12.2):

| Measurement | Result |
| --- | ---: |
| Empty-script bypass, 30 samples | median 0 µs; p95 1 µs |
| First script | 3,151 µs |
| Warm scripts, 500 samples after 30 warmups | median 943 µs; p95 1,244 µs |
| RSS before / after warmup / after 500 | 15,286,272 / 19,824,640 / 21,610,496 bytes |
| Native controls / runtimes after close | 0 / 0 |

Raw measurements are checked in at
`tool/scripting/benchmark-macos-arm64-2026-10-30.json`. Repeated script samples
measure runtime execution, not 500 network sends. Cold boot, real no-script HTTP
latency before/after and Windows/Linux performance remain unmeasured.

Bundled scripting artifact sizes (uncompressed): QuickJS WASM 518,880 bytes,
Worker 56,197 bytes, shared bootstrap 18,893 bytes. The arm64 AOT benchmark's
native library is 1,041,312 bytes; this is not a before/after application size
comparison or a signed desktop release measurement.

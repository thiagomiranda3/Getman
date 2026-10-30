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

- Full Flutter suite: **3,917 passing tests**, no failures.
- Line coverage: **94.72%** (25,147 / 26,548 instrumented lines, using the project coverage filters).
- Real Chrome runtime/API/snippet corpus: **56 passing tests**.
- Final macOS graphical integration: **147/147 passing cases in 7m54s**, with
  no skips, including all **11 scripting cases** (9 real HTTP/Hive/QuickJS
  contracts plus desktop editing/results and compact error visibility), native
  clipboard contents, the full theme matrix and legacy application flows.
- Browser integrationDriver journeys: **2 passing tests**, real production
  dependencies and local HTTP fixtures.
- Web release build: passed with `/Getman/` base href; bundled bootstrap,
  Worker and WASM bytes match the verified source assets.
- macOS arm64 release build: passed. The final **universal macOS release also
  passed (110.6 MB)**: `arm64` and `x86_64` verified independently in the app,
  FlutterMacOS, App and QuickJS binaries; strict deep signature verification
  passed. Host-only build workarounds and evidence are described below.
- Four independent static gates: zero analyzer, custom_lint, fixture self-test
  and bloc_lint issues. Dart formatting and owned-file whitespace checks clean.
  Upstream vendored C/license bytes retain their original whitespace so their
  recorded source hashes remain reproducible.

These results are local validation, not a completed cross-platform release
matrix. A diagnostic macOS integration aggregate completed **132 cases** before
stalling with lifecycle `hidden`, no scheduled frame and an idle scheduler.
macOS window occlusion prevented the live test binding from advancing. The
harness now restores its window through a DEBUG-only native channel while the
test owns it; its observer is removed before DI cleanup. The runner also uses
`caffeinate -di` when available, scoped to its bounded watchdog process. Neither
changes system power settings or release behavior. The next complete aggregate
finished without a stall: **146/147 passed**, with one Copy-confirmation failure.
Two deterministic widget tests then reproduced copying an empty editor on the
first response, or the old response during a resend, before JSON formatting
completed. Copy/Save now use the current raw body until its guarded formatting
sync finishes, then retain the formatted-text behavior. All **44 focused widget
tests** and **4 real macOS response-pane flows** passed. The integration assertion
checks native clipboard JSON and a visible acknowledgement without waiting for
formatting. The final clean aggregate after this fix passed **147/147** in
**7m54s**, exit 0, without skipped cases or hidden-window stalls.

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

The original universal build failed inside Flutter's `release_unpack_macos`:
the workstation's physical `lipo` rejects multi-argument `-verify_arch` even
when both slices exist. Real single-architecture checks and multi-extract work.
The opt-in `tool/scripting/macos_lipo_compat.py` wrapper expands only Flutter's
multi-architecture verification form into real checks for every requested slice;
a missing slice still fails. All other operations are forwarded unchanged.
It resolves the physical tool with `xcrun --find lipo` before installing a
subprocess-only proxy; Xcode shell-phase lookup needs
`__XCODE_BUILT_PRODUCTS_DIR_PATHS` as well as PATH. Temporary files and environment
are scoped to that command. Six real Mach-O/Xcode tests verify success, missing
slices, passthrough status/output, cleanup and preservation of caller xcconfig.

The **final universal release passed**, using only deployment target 12.0 in
the temporary xcconfig (no ARCHS restriction):

```sh
XCODE_XCCONFIG_FILE=/tmp/getman-scripts-e2e.xcconfig \
  python3 tool/scripting/macos_lipo_compat.py run \
  fvm flutter build macos --release --no-pub
```

At 17:28:47 UTC, independent physical-tool checks confirmed both `arm64` and
`x86_64` in Getman, FlutterMacOS, App and `getman_quickjs`; strict deep codesign
verification passed. Flutter reports **110.6 MB**; the fat QuickJS binary is
2,056,432 bytes. Per-binary sizes and hashes are in
[`macos-universal-2026-10-30.json`](../../tool/scripting/macos-universal-2026-10-30.json).
This verifies a universal build, not execution on an Intel Mac. No SDK, project
build setting or system executable was changed. The default host toolchain still
needs this opt-in workaround; the earlier arm64-only benchmark builds use their
separate temporary architecture override.

Windows/Linux are not executable on this workstation. The dedicated native
workflow compiles and runs the bridge on their corresponding runners, including
C11/MSVC atomics configuration. Their actual CI results must be checked before
claiming a verified multiplatform release. The user chose local-only validation:
no branch push, draft PR or remote CI execution is authorized for this follow-up.
The dedicated workflow is prepared locally; Windows/Linux remain unverified.
Existing release workflows remain unchanged; no product release or deployment
was initiated here.

## Runtime performance

`tool/scripting/benchmark.dart` can be compiled with:

```sh
fvm dart build cli --target=tool/scripting/benchmark.dart --output=/tmp/getman-scripts-benchmark
/tmp/getman-scripts-benchmark/bundle/bin/benchmark
```

It measures an empty-script bypass, first script, 30 warmup runs and 500
subsequent executions in the AOT runtime. RSS includes the VM/allocator and is
not the JavaScript heap limit. Native ownership counters complement RSS.
This standalone runtime benchmark does not establish app startup or HTTP
latency. The separate release-app comparison below measures those paths.

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
measure runtime execution, not 500 network sends. Windows/Linux performance
remains unmeasured.

Bundled scripting artifact sizes (uncompressed): QuickJS WASM 518,880 bytes,
Worker 56,197 bytes, shared bootstrap 18,893 bytes. The arm64 AOT benchmark's
native library is 1,041,312 bytes; this is not a before/after application size
comparison or a signed desktop release measurement.

## Release-app before/after performance

The reproducible harness, retained attempts and raw data live in
[`tool/scripting/performance/`](../../tool/scripting/performance/README.md).
It runs real release apps, MyApp/DI, isolated empty Hive, TabsBloc SEND, Dio,
history and a local HTTP server. Baseline is `662dd548`, before JavaScript.
The final app includes both response-controller and pending-copy fixes; its
source fingerprint and Dart AOT hash are recorded in each dataset.

The first comparison found repeated no-script p95 increases of 52.5%/55.0%.
A widget regression test reproduced controller recreation on every execution ID
change. Keeping the response controller stable without script errors preserves
its selected tab; a new error still opens CONSOLE on the first frame. An
isolated A/B confirmed lower SEND tail latency after that fix. The subsequent
full GUI run found the pending-copy bug described above, so the final app was
rebuilt and measured again rather than claiming the older artifact was final.

Final-tree measurement ran **17:23:36–17:25:47 UTC**. Its first startup batch
crossed the 10% investigation threshold (+14.33%), while its second did not
(+1.19%). One predefined repeat used the **same binaries**, without rebuilding,
**17:29:37–17:31:47 UTC**; its startup changes were +3.93%/+1.89%. All four
batches, including the two highest startup samples, are retained. No cause is
assigned to the initial alert, and it is not relabeled as an all-batches pass.

Each batch contains 30 fresh processes per version, with ten HTTP warmups and
30 measured SENDs per process. Across both runs: **240 measured processes,
7,200 measured no-script SENDs**, plus separate warmup/script processes.
Exact-child-PID AppKit activation after first-frame telemetry prevents hidden
window stalls. Both versions use the same launcher and temporary arm64/
deployment-12 build override.

| Pooled p95 metric | Baseline | Final app | Change |
| --- | ---: | ---: | ---: |
| Dart main → first rasterized frame, 120 samples/version | 80.508 ms | 82.568 ms | +2.56% |
| Host launch → first-frame report, 120 samples/version | 369.888 ms | 374.501 ms | +1.25% |
| No-script SEND, 3,600 samples/version | 1.700 ms | 1.710 ms | +0.59% |

No-script p95 changes by batch were −1.61%, −0.22%, +6.83%, −2.24%: all below
10%. The startup alert did not repeat; the pooled figures supplement rather
than erase the individual batch results. These are fresh processes with empty
storage and warmed filesystem caches, not cold-OS or populated-workspace
measurements. Host launch includes telemetry transport. No outliers are removed.

Each final run also completed **500 real scripted HTTP SENDs** after 30 warmups:
medians **3.386 / 3.380 ms**, p95 **4.174 / 4.083 ms**. Every send ran both hooks,
mutated a header verified by the server and passed two post-response assertions.
Independent first scripted SENDs without a native probe took **9.229 / 12.424 ms**
(one sample per run). Native controls/runtimes were **0/0** before scripts,
after each 100 sends and after disposal. RSS snapshots are retained in both raw
reports; RSS is process allocator usage, not a direct guest-heap measurement or
universal memory-leak guarantee.

Instrumented arm64 bundles grew from 55,646,277 to 57,419,371 bytes
(**+1,773,094 bytes**), not universal shipping sizes. The pooled report records
source-dataset hashes and both artifact hashes. Successful process samples are
now checkpointed before launching the next process; three regression tests
cover later-process failures, and the complete host suite has **14 passing tests**.
Measured runner sources are archived so earlier hashes remain reproducible.

Earlier runs affected by a recursive build-tool probe, plus an incomplete
hidden-window run, remain explicitly excluded in the invalidation manifest.
Their samples are not used for the final-tree consolidated result.

## Delivery scope and release authorization

The validation above was completed locally: at that point there had been no
branch push, draft PR, remote CI run, release or deployment. Windows/Linux were
not yet verified; response-usage wiki changes were committed locally only.
The earlier scripting wiki publication was unchanged.

On 2026-10-30 the user subsequently authorized pushing all completed work,
integrating it into `master`, and publishing tag **v1.12.0** to trigger the
release workflow. Remote CI and release results are recorded in GitHub Actions;
the local measurements above remain the evidence for the tested local artifacts.

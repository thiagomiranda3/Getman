# Release application performance comparison

This harness runs the actual desktop app and dispatches `TabsBloc.SendRequest`.
DI, Hive, Dio, history and the visible app are real. The fixture is a local HTTP
server returning a fixed 23-byte JSON body. Every process creates a new temp
Hive directory; no user's saved app data is opened. Startup update checks are
disabled identically through SettingsBloc before mounting either app.

Two different boot metrics are reported:

- `dart_main_to_first_raster_us`: fresh Dart main entry through media setup,
  fresh Hive/DI, disabling update checks and the real MyApp's first rasterized
  frame. It excludes native engine/process startup and persisted-user-data load.
- `host_launch_to_first_frame_report_us`: host process launch through receipt
  of that first-frame telemetry. This includes native startup and loopback
  telemetry overhead; it is not a pure first-frame timestamp.

The harness does **not** relabel a DI reset as cold boot. These are fresh-process,
empty-storage startup measurements with warmed filesystem caches, not a cold OS
or a populated-workspace benchmark. The benchmark entrypoint reproduces normal
startup initialization but intentionally uses temporary storage instead of
`Hive.initFlutter`; no workspace bookmark exists to resume.

The host requests AppKit foreground activation for the exact child PID after
first-frame telemetry and confirms `isActive`. This reduces hidden-window frame
stalls while retaining direct process ownership and timeout cleanup. Activation
is not synchronized with the app warmups; no claim about that ordering is made.
The initial historical run did not include this host activation helper.

Each revision gets three discarded startup warmups, followed by two independent
batches of 30 fresh processes. Baseline/current order alternates each pair and
reverses in batch two. Each process sends ten unrecorded HTTP warmups followed
by 30 timed real SENDs (900 HTTP samples per revision/batch). Timing begins at
BLoC dispatch and ends at its completed response emission, including the request
pipeline and history persistence; the next sample waits for the next frame.
First-frame elapsed time excludes the fixture report itself. Raw samples and
RSS are retained; no outlier removal is performed. p95 uses nearest rank, median
uses the average of the two center values for even samples.

A separate current-revision process performs the same plain sends, then one
first scripted SEND, 30 scripted warmups and 500 scripted SENDs. Each scripted
SEND executes both pre-request header mutation and post-response JSON/status
tests. The fixture requires `X-Answer: 42` on all 531 scripted requests,
and the app requires both hooks and exactly two post tests. Script errors and failed assertions abort the benchmark. Native controls
and runtimes must be zero before the first script and after DI disposal. The
pre-script ownership probe resolves the native bridge before the first timed
script; that sample is the first engine execution and asset load after the probe.
A separate `script_cold_first` process omits every pre-script native probe and
measures one first scripted SEND after the plain HTTP phase, including lazy
bridge resolution. It requires zero native ownership after disposal. RSS and
ownership counters are also sampled every 100 sends, with zero native ownership
required at all five checkpoints. RSS is process allocator
usage, not guest heap occupancy; native counters directly track live ownership.

The 10% p95 comparison is an **alert for investigation** if exceeded in both
batches; a single exceeded batch is `repeat_inconsistent`, never a silently
accepted pass. Baseline/current app bundle sizes are exact summed regular-file
bytes (symlinks excluded) of these instrumented release builds, not shipping
universal binaries. The source baseline/current revisions and executable hashes
are retained with the result.

## Final-tree local result — 2026-10-30

A **single predefined repeat** investigated the first batch's startup alert,
using the exact same saved binaries and harness with no rebuild. Its complete
[raw dataset](results-macos-arm64-final-tree-repeat-2026-10-30.json) was collected
**17:29:37–17:31:47 UTC**. No further repetition was selected based on outcomes.
The [four-batch consolidation](results-macos-arm64-final-tree-pooled-2026-10-30.json)
includes hashes of both source datasets, all four batch summaries and pooled
statistics from every sample. Neither 90 ms startup spike was removed.

| Final-tree batch | Dart startup p95, baseline → current | Change | No-script SEND p95, baseline → current | Change |
| --- | ---: | ---: | ---: | ---: |
| First run, 1 | 78.835 → 90.135 ms | +14.33% | 1.615 → 1.589 ms | −1.61% |
| First run, 2 | 82.823 → 83.809 ms | +1.19% | 1.780 → 1.776 ms | −0.22% |
| Predefined repeat, 1 | 78.623 → 81.712 ms | +3.93% | 1.787 → 1.909 ms | +6.83% |
| Predefined repeat, 2 | 79.771 → 81.281 ms | +1.89% | 1.696 → 1.658 ms | −2.24% |

| Pooled metric | Samples per revision | Baseline p95 | Current p95 | Change |
| --- | ---: | ---: | ---: | ---: |
| Dart-main → first raster | 120 | 80.508 ms | 82.568 ms | +2.56% |
| Host launch → first-frame report | 120 | 369.888 ms | 374.501 ms | +1.25% |
| No-script SEND | 3,600 | 1.700 ms | 1.710 ms | +0.59% |

**All four no-script HTTP batches remain within the 10% criterion.** The initial
startup alert remains visible (one of four batches exceeded 10%); it did not
repeat in the other three batches. The pooled result does not erase that
inconsistency or establish its cause. No universal “every startup p95 below
10%” claim is made.

The unchanged runner also completed its scripted phases in the repeat:
500 sends had median 3.380 ms / p95 4.083 ms, compared with 3.386 / 4.174 ms in
the first final-tree run. Unprobed first sends were 9.229 and 12.424 ms (one
sample each); probed first sends were 10.828 and 10.009 ms. Both runs retained
zero native controls/runtimes at every ownership checkpoint and after disposal.
All script samples remain in their respective raw datasets; no preferred run
was selected. The first final-tree run's detailed measurements follow.

[`results-macos-arm64-final-tree-2026-10-30.json`](results-macos-arm64-final-tree-2026-10-30.json)
is the first full final-tree dataset, collected **17:23:36–17:25:47 UTC** after the
response controller and pending-formatting Copy fixes. It supersedes the
17:05 dataset for final-tree claims; all previous data remains preserved.
All **120 measured processes**, six startup warmups and two scripted processes
completed, with exact-PID activation confirmed. Both repeated batches contain
30 app processes per revision and 900 no-script HTTP samples per revision.

| p95 metric | Baseline batches 1 / 2 | Final tree batches 1 / 2 | Change |
| --- | ---: | ---: | ---: |
| Dart-main → first raster | 78.835 / 82.823 ms | 90.135 / 83.809 ms | +14.33% / +1.19% |
| Host launch → first-frame report | 368.881 / 381.873 ms | 374.365 / 379.450 ms | +1.49% / −0.63% |
| No-script SEND | 1.615 / 1.780 ms | 1.589 / 1.776 ms | −1.61% / −0.22% |

**The repeated no-script HTTP p95 criterion is within 10% in both batches.**
Dart startup is classified **`repeat_inconsistent`**: the first batch exceeds
10%, while the second does not. Do not claim that all startup p95 results are
within 10% or that the one-batch startup alert proves a regression. The first
batch's two slowest current startups were 90.135 and 90.309 ms; the third was
81.924 ms. Startup medians were slightly lower in current in both batches
(70.2215 → 69.784 ms and 69.0095 → 68.6095 ms). These observations describe
variability without assigning an unmeasured cause.

No-script SEND medians were 0.883 / 0.876 ms baseline and 0.9155 / 0.916 ms
current. The first scripted SEND without a native probe took **9.229 ms**
(one sample), and the first after the probe took **10.828 ms** (one sample).
After 30 warmups, **500 real scripted SENDs** had median **3.386 ms** and
p95 **4.174 ms**; every pre-hook header and both post-hook tests were checked.

RSS before scripts / after warmups / after 500 / after disposal was
156,614,656 / 160,759,808 / 163,627,008 / 165,085,184 bytes. Native controls and
runtimes were zero before the first script, at all five 100-send checkpoints,
and after disposal. RSS is retained allocator/process memory, not a leak
verdict. Instrumented bundle bytes remain 55,646,277 → 57,419,371
(+1,773,094 bytes), with native executable and Dart AOT hashes recorded.

The built tree is `5c5a4e8c` plus the two-file `lib` diff with SHA-256
`06eac93ff0f5c2d30dea2fbf2464286cf876e93c7d0ab30ba282a8b95346cb50`:
`response_section.dart` preserves ordinary response controller identity;
`response_body_view.dart` copies the active raw body while formatting is pending.
The final measured host is archived as
[`historical/runner-final-tree.py`](historical/runner-final-tree.py), with
harness hash `9c4c3689882f8eeec65ef824f1494041668ca70d521ead0916501c8ebc631ddb`.
The generated app entrypoint was removed after the build. This is macOS arm64
release evidence only; Windows/Linux performance remains unverified.

## Prior accepted result — response controller fix

[`results-macos-arm64-fixed-2026-10-30.json`](results-macos-arm64-fixed-2026-10-30.json)
is the earlier response-controller dataset, collected **17:05:53–17:08:04 UTC**, after all
interfering work stopped. All 120 measured app processes completed: two batches
of 30 alternating baseline/current pairs, 900 no-script HTTP samples per
revision/batch. Six startup warmup processes and two separate scripted processes
also completed. Every measured process confirmed exact-PID foreground activation.

| p95 metric | Baseline batches 1 / 2 | Fixed current batches 1 / 2 | Change |
| --- | ---: | ---: | ---: |
| Dart-main → first raster | 81.261 / 77.346 ms | 82.930 / 83.391 ms | +2.05% / +7.82% |
| Host launch → first-frame report | 379.332 / 375.105 ms | 380.440 / 379.538 ms | +0.29% / +1.18% |
| No-script SEND | 1.594 / 1.558 ms | 1.645 / 1.570 ms | +3.20% / +0.77% |

**Both repeated no-script p95 batches are within the 10% threshold.** No-script
medians were 0.781 / 0.7835 ms baseline and 0.8075 / 0.8225 ms fixed current.
The final first scripted SEND without a native probe took 11.359 ms (one
sample), and the first after the probe took 10.529 ms (one sample). After 30
warmups, **500 real scripted SENDs** had median **3.4295 ms**, p95 **4.158 ms**.

RSS before scripts / after warmups / after 500 / after disposal was
161,906,688 / 159,285,248 / 159,432,704 / 160,825,344 bytes. Native controls and
runtimes were zero before the first script, at all five 100-send checkpoints,
and after disposal. Bundle sizes remained 55,646,277 → 57,419,371 bytes
(+1,773,094 bytes). The final dataset records both native executable and Dart
`App.framework` AOT hashes, the harness hash, runtime versions and raw samples.

The original tail increase was traced to the response `DefaultTabController`
being keyed by every execution ID, recreating the response subtree on ordinary
sends and losing its selected tab. A widget regression test demonstrated the
controller replacement. The isolated fix keeps its identity for ordinary sends
and still recreates it when a new script error needs diagnostic focus; no
pipeline fast path or script behavior was changed. The clean six-pair
[A/B dataset](response-controller-ab-2026-10-30.json) used identical app harnesses
and only this product change: p95 **2.365 → 1.646 ms** over 180 HTTP samples per
variant. Its patch SHA-256 and both AOT hashes are recorded. The final full gate
then compared the fixed app against pre-JavaScript baseline `662dd548`.

Current source is identified as `0f73cc5c` plus response-controller patch
`c2746ff14a886dc7721bfc70b44793f08fdd72db11bc38eb39e0c13ed364db03`.
This is local macOS arm64 evidence; it does not establish Windows/Linux or
universal shipping build performance.

### Retained attempts and exclusions

[The exclusion manifest](invalidated-measurements-2026-10-30.json) records the
recursive native-tool probe interference window, 16:51:15–16:55:17 UTC. Files
with `contaminated` in their names are retained but excluded from conclusions.
A later direct-launch run stopped after five complete pairs when a baseline
window stopped scheduling frames; its partial JSON/logs are retained as
`incomplete-direct` and are not a passing run. The clean direct-launch A/B was
also retained, then repeated with PID activation to match the final host setup.
The initial 16:41:22–16:43:32 dataset predates the interference window.

`historical/runner-direct.py` preserves the original host source corresponding
to the initial dataset's harness hash; its app template and prepare script are
unchanged. The two final-tree datasets and their four-batch consolidation determine the
final source-tree result.

## Measured host version and subsequent checkpoint fix

The earlier 17:05 dataset was collected with
[`historical/runner-accepted.py`](historical/runner-accepted.py); the measured A/B
loop is preserved in
[`historical/compare-accepted.py`](historical/compare-accepted.py). These copies
retain their measured bytes. The current `runner.py` and `compare.py` now write
a JSON checkpoint after **each successful measured application process**, so a
failure in the second half of a pair preserves its completed partner. The
500-script report is also written before starting the separate cold-script
process. Incomplete checkpoints have neither the final summary nor completion
timestamp and must not be interpreted as a passing run. Startup warmups remain
intentionally discarded.

This later change affects host checkpointing only. No app was rebuilt or
benchmark repeated for that fix alone; all earlier JSON samples and hashes
remain unchanged. The later final-tree repeat was required by the product Copy
fix and used the corrected host archived in `historical/runner-final-tree.py`. Three host regression tests inject failures at the application
boundary and assert the successful telemetry survives in the real output file.

To verify the final-tree dataset's exact harness hash from the repository root:

```sh
python3 - <<'PYHASH'
import hashlib
import json
from pathlib import Path
root = Path('tool/scripting/performance')
digest = hashlib.sha256()
for name in ('runner.py', 'prepare.py', 'app.dart.template', 'foreground.py'):
    source = root / ('historical/runner-final-tree.py' if name == 'runner.py' else name)
    digest.update(name.encode())
    digest.update(source.read_bytes())
recorded = json.loads((root / 'results-macos-arm64-final-tree-2026-10-30.json').read_text())
assert digest.hexdigest() == recorded['harness_sha256']
print(digest.hexdigest())
PYHASH
```

For a byte-identical final-tree host replay, copy `historical/runner-final-tree.py`
as `runner.py` into a
separate temporary directory alongside the unchanged `prepare.py`,
`app.dart.template` and `foreground.py`, then use the commands below from that
copy. Future normal runs should use the current runner with complete checkpoints.

## Reproduce on macOS

Use two isolated source checkouts, one at the pre-JavaScript baseline
`662dd548` and one at the current revision. Do not run Flutter builds or tests
concurrently; also keep the workstation quiet during measurements.

```sh
python3 -m unittest discover -s tool/scripting/performance -p 'test_*.py'
python3 tool/scripting/performance/prepare.py /tmp/getman-performance-baseline
python3 tool/scripting/performance/prepare.py /tmp/getman-javascript-scripts --current
```

In **each checkout**, build through FVM, serially:

```sh
fvm flutter pub get
fvm flutter build macos --release --target lib/performance_main_io.dart
```

On this workstation only, Xcode needs a temporary xcconfig supplied via
`XCODE_XCCONFIG_FILE` containing `MACOSX_DEPLOYMENT_TARGET = 12.0`,
`ARCHS = arm64` and `ONLY_ACTIVE_ARCH = YES`. Apply the identical override to
both builds. This does not alter SDK files or product deployment configuration.
Copy each built `.app` to a distinct temporary directory before other Flutter
work can rewrite it. Then:

```sh
python3 tool/scripting/performance/runner.py \
  --baseline /tmp/getman-performance-apps/baseline.app/Contents/MacOS/getman \
  --current /tmp/getman-performance-apps/current.app/Contents/MacOS/getman \
  --baseline-revision 662dd548 --current-revision CURRENT_SHA \
  --output tool/scripting/performance/results-macos-arm64.json
```

Remove generated `lib/performance_main_io.dart` from both checkouts after the
build. It is benchmark-only and must not ship. A failed sample aborts and keeps
per-process logs; it must be investigated instead of removed from the dataset.
Failed runs intentionally retain their synthetic Hive directory and process
logs for diagnosis; only successful app runs delete their temporary Hive data.
The runner needs permission to bind its loopback fixture port and launch GUI
processes. Windows/Linux require their own measurements; macOS results do not
establish their performance.

## Initial measurement and investigation — 2026-10-30

[`results-macos-arm64-2026-10-30.json`](results-macos-arm64-2026-10-30.json)
contains the full raw dataset for baseline `662dd548` and current `0f73cc5c`,
Flutter 3.44.4 / Dart 3.12.2, macOS 27.0.1 arm64, Apple M3 Max / 36 GiB.
The run completed from 16:41:22 to 16:43:32 UTC. Both apps used the same temporary
arm64 / macOS 12 deployment override and the shared harness identified by its
SHA-256 in the JSON. Uncommitted integration helper changes were not imported;
the current native activation addition is DEBUG-only and absent from release.

| Metric | Baseline, batches 1 / 2 | Current, batches 1 / 2 |
| --- | ---: | ---: |
| Dart-main → first raster p95 | 84.406 / 81.145 ms | 84.107 / 80.625 ms |
| Host launch → first-frame report p95 | 373.414 / 375.381 ms | 388.325 / 376.305 ms |
| No-script SEND median | 0.8205 / 0.821 ms | 0.8285 / 0.836 ms |
| No-script SEND p95 | 1.573 / 1.609 ms | 2.399 / 2.494 ms |

**The no-script p95 alert fired in both batches: +52.5% and +55.0%.** Startup
stayed within the 10% threshold. The no-script tail increase is reproducible in
this workload and led to the isolated lifecycle fix and final rerun above. This
initial dataset does not establish a performance gate pass. All outliers and every process's samples are retained.

The separate unprobed first scripted SEND took 9.665 ms (one sample); the first
SEND after the native ownership probe took 6.278 ms (one sample). The 500
subsequent scripted SENDs after 30 warmups had median 3.233 ms and p95 4.604 ms.
Each send executed both hooks and passed two post-response tests, with its
pre-request header verified at the real HTTP server.

RSS before scripts / after 30 warmups / after 500 / after disposal was
159,383,552 / 171,147,264 / 170,737,664 / 160,006,144 bytes. Native controls and
runtimes were zero before the first script, at each 100-send checkpoint and
after disposal. These counters establish released native ownership; the RSS
values alone do not establish absence of every possible memory leak.

Instrumented arm64 release bundle bytes were 55,646,277 baseline and 57,419,371
current, an increase of 1,773,094 bytes. These include the benchmark entrypoint
and are not measurements of universal shipping artifacts.

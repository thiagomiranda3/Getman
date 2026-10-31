# Native startup and editor measurements

This is a non-shipping release entrypoint using the real `StartupGate`, `MyApp`,
DI, storage worker and widgets. It seeds a separate temporary Hive directory
inside the app sandbox. Updates are disabled in that fixture. No real Getman Hive
workspace is opened. The runner activates only the child PID it started, receives
loopback HTTP reports, checkpoints every report and kills only its own child
on failure. It generates a temporary one-day self-signed client certificate;
the mTLS case configures a client but does not make a remote connection.

## Reproduce

Use the pinned SDK. On the measured Apple Silicon machine, the temporary
xcconfig contained `MACOSX_DEPLOYMENT_TARGET = 12.0`, `ARCHS = arm64` and
`ONLY_ACTIVE_ARCH = YES`. This avoids building an unused architecture and
retains the normal app sandbox. Put those three lines in `/tmp/getman-perf.xcconfig`.

```sh
XCODE_XCCONFIG_FILE=/tmp/getman-perf.xcconfig fvm flutter build macos --release --no-pub --target tool/performance/app.dart
cp -R build/macos/Build/Products/Release/getman.app /tmp/getman-perf-current.app
python3 tool/performance/run.py /tmp/getman-perf-current.app/Contents/MacOS/getman tool/performance/local-result.json --revision 'describe the exact source revision' --baseline /tmp/getman-perf-before.app/Contents/MacOS/getman
```

For a baseline, build the same harness against `3ec67025` in an isolated
checkout and copy its bundle to the other path first. The harness's editor
lookup uses existing public widgets and also compiles at that revision.
Do not overwrite a copied bundle; use a fresh destination per build.
The runner records executable/AOT hashes, harness hashes, and (in the final
version) current `lib/**/*.dart` hashes. Build before running; the source hash
map describes the current checkout, not an independently supplied baseline.

Ten fresh-process samples per variant and fixture alternate before/after
order. `--counts 0 --runs 1` is useful for a shorter workload run;
`--skip-workloads` measures startup only. `--sample-editors` adds native stack
sampling for diagnosis; **do not use sampled runs as clean timing evidence**.
Do not run builds, tests or other benchmarks concurrently. Keep the machine
awake. This activates real windows; run when foreground interaction is idle.

## Fixtures and definitions

- Startup: empty persisted tabs, or 500 persisted tabs with 128 KiB response
  text each (62.5 MiB). App boot may seed its normal initial tab for the empty
  fixture. Filesystem caches are warm; process launches are fresh. This does
  not measure OS cold-cache launches, Finder clicks or every production theme.
- `first_frame_us`: Dart `main` entry to `waitUntilFirstFrameRasterized`.
  `first_frame.host_elapsed_us`: host process launch to receipt of that
  telemetry; includes native startup and loopback reporting overhead. It is
  an approximation above process-to-raster time, not exact native tracing.
- `workspace_frame_us`: Dart entry to tabs/collections readiness plus
  `endOfFrame`. This is a UI frame boundary, **not a raster completion**.
- `max_gap_us`: largest interval between 1 ms timer callbacks on the UI
  isolate; includes scheduling delay, not exclusively CPU work.
- `frames`: raw Flutter build/raster/total timings. Reports drain frame
  callbacks for 1.1 seconds; measurements also wait 1.1 seconds before work.
  `elapsed_us` includes the awaited frame boundary, so is not pure CPU time.
- Work: raw JSON containing 40,000 objects with `{{value}}` substitution;
  GraphQL variables containing 80,000 objects; JSON nesting depth 1,000;
  RSA-2048 PEM/key local-file client configuration. Five sequential rounds of
  each. Worker results preserve raw data; serializer correctness is also
  covered by automated tests.
- Editor: the same raw JSON in one line, then pretty-printed across lines,
  opening the actual BODY section. One sample per shape per workload process.
  Observe 600 ms after tab insertion plus frame-callback drain; final harness
  also checks that the real editor is mounted with the complete body. Earlier
  harness versions used the fixed observation interval without this check.
  Final harness additionally opens find on the single line and searches for
  `39999` near its end, asserting that a window no longer than 4,100 characters
  contains the match. The query case includes the 180 ms debounce and waits
  600 ms for the scan and frame; it does not claim pure search CPU latency.
- RSS: process-wide current/peak resident memory, including engine/workers.
  A peak is not a memory leak diagnosis or a per-isolate allocation count.

## Retained evidence

All samples are retained; there is no outlier filtering. Do not infer p95
from five workload rounds or a single editor sample.

| File | Meaning |
|---|---|
| `baseline-macos.json` | 10 empty startups and five pure-work rounds at `3ec67025`; **incomplete** because opening the huge single-line editor exceeded 120 seconds. The initial runner did not annotate this failure in JSON. No completed editor measurement exists in this file. |
| `baseline-populated-macos.json` | 10 populated baseline startups, complete. |
| `after-v1-macos.json` | Text-body worker + bounded highlighting; 10 alternating startup pairs per fixture, five work rounds and one editor sample per shape. |
| `diagnostic-v1-macos.json` | Native stack sampling run. Diagnostic only. |
| `after-v2-macos.json` | Additionally prepares controller lines off the UI isolate. |
| `after-v3-macos.json` | Additionally limits rendered single-line length. |
| `before-windowed-find-macos.json` | 10 alternating startup pairs per fixture, workloads, readiness validation and the find-open diagnostic that exposed the 505 ms stall. |
| `final-attempt-foreground-failure*.json` | Two incomplete attempts where AppKit activation was rejected. Excluded from successful-startup comparisons, retained as failures. Retrying the activation request after raster telemetry allowed subsequent runs to finish; a launch-readiness race is the suspected cause. |
| `final-macos.json` | Includes the windowed-find guard and all other runtime changes; successful startup pairs, workloads, full editor readiness and tail-match validation. |

The intermediate labels identify incremental working-tree states, not Git
commits. Their binary/harness hashes distinguish those states, but binaries and
native stack samples in temporary directories are not durable artifacts.
See [the performance report](../../docs/PERFORMANCE.md) for findings and limits.

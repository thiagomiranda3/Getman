# Performance: profiling Getman

Getman uses worker isolates for several CPU-heavy operations and narrowly gates
BLoC rebuilds. This is not a guarantee of zero stalls: `async` and debouncing
alone do not move CPU work off the UI isolate. This document records the
remaining risks and a repeatable profiling procedure.

## Timeline instrumentation

Key pipeline spans are wrapped with `dart:developer` Timeline events (see
`lib/core/utils/perf_trace.dart` — `traceSync` / `traceAsync`). These are
no-ops in release builds, so they're free to leave on the hot path.

Current spans:

| Event | Where | What it covers |
|---|---|---|
| `startup.settings` | `main` | minimum persisted appearance before first frame |
| `startup.services` | `main` | feature stores, migrations, DI and workspace bookmark after first frame |
| `send.request` | `SendRequestUseCase` | URL/auth/body assembly + the network round-trip |
| `send.recordHistory` | `SendRequestUseCase` | best-effort history write |
| `tabs.putTab` | `TabsBloc._flushDirtyTabs` | debounced incremental tab persistence |

## How to profile

```
fvm flutter run -d macos --profile
```

Open DevTools → **Performance**. Record while exercising each scenario, then
check the **UI** track for frames over budget (~16 ms) and the **Timeline
Events** for the spans above:

1. **Large response + JavaScript scripts** — send a request returning a multi-MB
   JSON body with post-response lookups/assertions. QuickJS runs off the UI
   isolate; the UI thread should not spike. See [scripting verification](architecture/scripting-verification.md)
   for measured runtime costs and remaining app-wide benchmarks.
2. **High-rate stream** — connect an SSE/WebSocket source that emits rapidly.
   Frames coalesce (~1 emission per 16 ms window); the live panel should scroll
   without dropping frames.
3. **Cold start** — relaunch with real data (large `tabs.hive` / `history.hive`).
   Only settings open before the loading window; other Hive boxes open after
   the first frame in the native storage worker. Cookies hydrate before request controls are exposed. QuickJS loads lazily on the
   first nonempty script.
4. **Rapid edits** — create/rename/move collections, edit environments, trigger
   `Set-Cookie` responses. Environments/cookies persist per-key (no whole-list
   rewrite); collections persist immediately; workspace mirror writes are debounced.
5. **Splitter drag + search typing** — dragging the split divider relayouts the
   panes without rebuilding the editors; search fields are debounced (~220 ms)
   and only the results list rebuilds.

If a scenario shows a UI-isolate stall, capture the offending Timeline span and
open an issue with the trace.

## Audit — 2026-10-31

### Implemented

- **First frame:** settings only before `runApp`; feature stores, migrations,
  cookie hydration and workspace access follow the themed first frame. A failure
  remains visible. MediaKit loading moved from `main` to first playback.
- **Workspace:** whole native read/write operations run in an isolate, including
  JSON serialization, recursive scans and reconciliation. Flush/suspension and
  atomic-file semantics remain in force.
- **Git:** filesystem existence and identity checks are asynchronous (network
  mounts can stall even a seemingly tiny stat call).
- **Responses:** UTF-8/Latin-1 decoding above 64 KiB runs in a worker, with a
  cancellation check before publishing the result.
- **Import/export:** large Postman/OpenAPI parsing and text decoding use workers;
  Postman/API-doc export serialization uses workers. Export reuses encoded bytes.
- **Native persistence:** a persistent isolate owns all nine feature boxes.
  Repository RPC moves box decoding, legacy migrations, model conversion,
  history dedup/sorting and write serialization off the UI isolate. Settings
  stay UI-side. Existing file formats, caps, watcher semantics and boot cookie
  hydration are preserved; close drains accepted writes, and the exit guard
  awaits a storage flush after debounced saves. Media buffers and transient
  script state are stripped before sending tabs across the port. Details and
  the `IsolatedHive`/`HiveObject` constraint are in
  [storage ownership](architecture/persistence-hive.md#storage-ownership).

### Remaining risks and measurement priorities

| Priority | Evidence in current code | Next change / measurement |
|---|---|---|
| P1 | Native feature persistence now has a worker, but settings and live cookie matching remain UI-side. RPC copies mutable graphs, and one FIFO owner can queue behind a large collection write. | Profile huge collections/headers and write bursts; consider bounded batches or incremental snapshots if transfer costs or queue depth exceed budget. Keep feature boxes exclusive to their owner. |
| P1 | Controller application, multiline layout, body completion and unresolved-variable scans can still execute UI-side. | The measured huge-line find stall now uses bounded search windows. Further profile typing/paste/Beautify and theme changes, not just initial open. Moving parsers alone does not move Flutter layout; simply truncating controllers would corrupt requests. |
| P1 | Collection sorting/filtering, command-palette matching, script protocol encoding/validation and MCP JSON have not been covered by the release corpus below. | Profile large collection counts and protocol payloads before choosing batching, indexes or more workers. Large raw/GraphQL preparation now has a worker, but small input expanding through very large environment values remains a risk. |
| P2 | `dio_adapter_config_io.dart` uses synchronous `SecurityContext.useCertificateChain/usePrivateKey` at configuration and WS connect. Local synthetic certificate setup measured a small delay; slow filesystems and larger chains remain untested. | Defer a transport-owner redesign on the evidence available. Async file loading plus a transport isolate may be appropriate if those cases exceed budget. SecurityContext/socket objects cannot simply be sent with `compute`; preserve errors and config/cancellation ordering. |
| P2 | JSON prettification can expand deeply nested input; isolates share the process memory budget. Depth 1,000 kept the UI responsive in this corpus, but there is no total output/memory bound. Response caps are per response, not across all tabs/history. | Test output growth and total-memory pressure, then add explicit user-facing fallbacks before claiming robustness to arbitrary input. |
| P2 | `compute` is synchronous on Flutter web; engine startup, native plugin registration, fonts, GPU/raster work and OS scheduling are outside these Dart workers. | Dedicated web Workers for heavy web paths; native profile/release traces and cold-start measurements on target machines. |

The 64 KiB cutoff is an engineering starting point, not a measured guarantee on
all hardware. Worker startup/message copying have costs, so trivial operations
should stay local. Widgets, controllers and painting must remain on the UI
isolate. More worker isolates are not automatically faster.

### Measurement acceptance

Record separate values for process launch → first rasterized frame and launch
→ usable workspace. `startup.settings`/`startup.services` are partial Dart spans,
not a substitute for process-to-frame measurement. Compare the base commit and
this revision with the same SDK, profile/release mode, machine and isolated data
fixtures (empty; many tabs/history; large collections). Repeat cold and warm
launches and report median/p95, UI and raster frame times, max event-loop delay,
and peak RSS. At 60 Hz use 16.7 ms as the frame budget; at 120 Hz use 8.3 ms.
Exercise imports, large responses, canceled sends, scrolling, editing, stream
bursts and Git operations while input/animations remain active.

Automated correctness tests verify theme/order, storage readiness, worker
round-trips and lifecycle. They **do not establish startup latency or zero jank**.
The release measurements below cover fresh processes with warm filesystem
caches. They do not establish OS cold-cache startup or a universal no-freeze
guarantee. This round makes no claim of improved startup latency.

### Storage scheduling measurement — 2026-10-31

Run the opt-in synthetic comparison separately from the test suite:

```sh
fvm flutter test --no-pub tool/storage_worker_benchmark.dart --reporter expanded
```

It creates temporary real Hive files with 500 tabs and 128 KiB of response text
per tab (62.5 MiB of body data), then reads the same bytes three times locally
and three times through the persistent worker, alternating order. A 1 ms timer
on the caller measures the largest gap between callbacks. Each sample includes
open/read/close; worker samples also open the other empty feature boxes. This
is Flutter 3.44.4 debug/JIT on the local macOS workstation, with warm filesystem
caches and **no widget rendering**. It measures scheduling, not process startup.

| Measurement | Local Hive | Persistent worker |
|---|---:|---:|
| Largest event-loop gap, samples (ms) | 201.715 / 195.639 / 192.321 | 2.765 / 2.587 / 2.753 |
| Median of largest gaps (ms) | 195.639 | 2.753 |
| Median total sample duration (ms) | 214.801 | 220.063 |

The worker kept the caller responsive while similar total work completed.
These three samples are evidence for this fixture, not a p95 estimate or a
maximum latency guarantee. Arbitrary object graphs, CPU contention and widget
build/layout still require the profile/release scenarios above. Correctness
tests separately cover existing-file migration/reopen, queued-write shutdown,
watcher cancellation/resubscription, cookie boot hydration, script trust,
failed commands/startup, duplicate-owner rejection and exit flush ordering.

References: [Flutter isolates](https://docs.flutter.dev/perf/isolates),
[Hive CE isolation](https://pub.dev/packages/hive_ce).

### Release measurements and targeted fixes — 2026-10-31

Measured on an Apple M3 Max with 36 GiB RAM, macOS 27.0.1, pinned Flutter
3.44.4, arm64 release/AOT. The real shell uses synthetic, isolated Hive data;
no user workspace is opened. Methodology, inputs, raw frame timings, hashes,
failed attempts and reproduction commands are in
[tool/performance](../tool/performance/README.md). Tests/builds and native
sampling were not running during the final timing collection.

The first baseline at `3ec67025` exposed the dominant issue: opening the
2,668,901-character minified body **did not complete within 120 seconds**.
Native sampling pointed to synchronous `re_highlight` work during widget
layout. A second diagnostic, after bounding that work, identified synchronous
re_editor line construction. These diagnostics guided the changes; sampling
runs are not used as clean latency measurements.

Implemented in this round:

- Raw substitution and GraphQL JSON preparation use a worker for inputs at
  least 64 Ki characters. Small requests retain the local path.
- Large request/GraphQL editor documents and Beautify results prepare lines
  asynchronously, with stale-result/disposal guards and undo preserved.
  Selection-only notifications do not repeatedly join the entire document.
- Lines over 8,192 characters skip optional syntax/variable coloring. Normal
  editor layout renders at most 16,384 characters per line plus an ellipsis;
  the full request remains in the controller for copy/save/send.
- Because re_editor removes that limit in find mode, oversized-line documents
  use the existing windowed search instead. It scans the full text in a worker,
  displays a 4 KiB region around each match and restores editing on close.
  No request content is truncated to implement these rendering budgets.

**UI-isolate scheduling gaps, milliseconds** (lower is better):

| Operation | Reference | Final | Samples / interpretation |
|---|---:|---:|---|
| Prepare raw body, 40,000 objects | 13.118 | 5.216 | Median of 5 rounds; ranges 12.858–18.592 vs 5.189–6.194 |
| Prepare GraphQL variables, 80,000 objects | 80.163 | 3.447 | Median of 5 rounds; ranges 77.026–86.904 vs 3.268–4.163 |
| Open minified editor, after highlighting was bounded | 563.270 | 24.095 | One sample each; reference is `after-v1`, not the original timed-out baseline |
| Open 200,004-line pretty editor | 362.060 | 50.068 | One sample each; reference is `after-v1` |
| Open find on the minified body | 504.585 | 6.041 | One sample each; reference is `before-windowed-find` |
| Find `39999` near the end of the minified body | — | 3.068 | One final sample; actual bounded snippet checked for the tail match |

Final worst reported build durations were 22.725 ms for minified editor open,
49.642 ms for multiline open, 4.774 ms for find open and 1.872 ms for the tail
query. The editor measurements are observations, **not p95 or maximum latency
guarantees**. Opening those extreme documents still exceeds a 16.7 ms frame
budget; controller application/widget layout remains a concrete next target.
Total operation duration includes waiting for a frame (and fixed observation
intervals for editors), so scheduling gains must not be read as equivalent
throughput gains. Final workload-process peak RSS was 266.5 MiB; there is no
completed original workload peak to make a fair memory comparison.

Two suspected bottlenecks did not justify a rewrite in this corpus: depth-1,000
JSON prettification had median gaps of 1.201 ms before / 1.288 ms after, and
local mTLS client configuration had 1.222 / 1.349 ms (first baseline setup
5.160 ms). Larger outputs, slow certificate filesystems and total-memory
pressure remain outside that evidence.

**Startup medians, milliseconds**, 10 alternating fresh-process pairs per
fixture in `final-macos.json`:

| Fixture / metric | `3ec67025` | Final |
|---|---:|---:|
| Empty: Dart entry → first rasterized frame | 28.870 | 28.926 |
| Empty: Dart entry → workspace UI frame | 67.725 | 72.818 |
| 500 tabs: Dart entry → first rasterized frame | 27.941 | 28.633 |
| 500 tabs: Dart entry → workspace UI frame | 400.981 | 400.310 |
| Empty: process launch → first-frame telemetry receipt | 301.263 | 258.704 |
| 500 tabs: process launch → first-frame telemetry receipt | 295.404 | 256.872 |

The 500-tab fixture stores 128 KiB of response text per tab (62.5 MiB). The
workspace metric ends at `endOfFrame` after tabs/collections readiness, not
raster completion. Host telemetry includes native launch and reporting
overhead, and activation happens after the first-frame report. It is **not a
Finder-click-to-visible-window measurement**. Host ranges overlap widely:
empty 206.328–329.081 ms before / 211.855–382.411 ms after. The final empty Dart
first-frame samples also include a 103.859 ms outlier; it was retained.

There is **no consistent Dart startup improvement in this round**. The lower
host median does not establish a causal native-startup improvement: this
round did not change native boot and was not a cold-cache OS experiment.
Settings/theme still precede the first frame; the workspace follows it. The
measured gains are chiefly responsiveness under large-body work. Arbitrary
inputs, web, all themes, high-rate streams, collection operations, clipboard
pastes, plugin calls and memory pressure require their own profiles before
claiming app-wide freedom from stalls.

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

### Remaining risks, in priority order

| Priority | Evidence in current code | Next change / measurement |
|---|---|---|
| P1 | Native feature persistence now has a worker, but settings and live cookie matching remain UI-side. RPC copies mutable graphs, and one FIFO owner can queue behind a large collection write. | Profile huge collections/headers and write bursts; consider bounded batches or incremental snapshots if transfer costs or queue depth exceed budget. Keep feature boxes exclusive to their owner. |
| P1 | `dio_adapter_config_io.dart` uses synchronous `SecurityContext.useCertificateChain/usePrivateKey` at configuration and WS connect. | Async certificate-file loading plus a transport owner isolate if parsing itself exceeds budget. SecurityContext/socket objects cannot simply be sent with `compute`. Preserve errors and config/cancellation ordering. |
| P1 | `request_view.dart`/re_editor controller construction, JSON highlighting, body completion, unresolved-variable scans, collection sorting/filtering and command-palette matching still execute UI-side. | Profile worst-case request size, single-line bodies, collection count and visible rows. Bound rendered work and use asynchronous snapshots with stale-result guards. Moving parsers alone does not move Flutter layout. |
| P1 | Script protocol encoding/validation, MCP JSON, request-variable substitution and GraphQL serialization remain CPU work on the caller. | Profile big inputs; move pure preparation/validation into workers without transferring cancellation handles, sockets or repository state. |
| P1 | JSON prettification can expand deeply nested input; isolates share the process memory budget. Response cap is per response, not total across tabs/history. | Add total-memory/output/work budgets with explicit user-facing fallbacks before claiming robustness to arbitrary input. |
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
No end-to-end cold-start or frame-time baseline was captured for this revision;
no numerical startup improvement or universal no-freeze claim is made.

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

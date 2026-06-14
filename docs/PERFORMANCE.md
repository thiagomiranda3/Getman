# Performance: profiling Getman

Getman is built to keep the UI isolate free: heavy work is moved off-thread
(`compute`), memoized, or debounced, and BLoC rebuilds are narrowly gated. This
doc explains how to verify there are no UI-isolate stalls.

## Timeline instrumentation

Key pipeline spans are wrapped with `dart:developer` Timeline events (see
`lib/core/utils/perf_trace.dart` — `traceSync` / `traceAsync`). These are
no-ops in release builds, so they're free to leave on the hot path.

Current spans:

| Event | Where | What it covers |
|---|---|---|
| `send.request` | `SendRequestUseCase` | URL/auth/body assembly + the network round-trip |
| `send.recordHistory` | `SendRequestUseCase` | best-effort history write |
| `rules.run` | `TabsBloc._applyRules` | extraction + assertions, decoded once (small body, inline) |
| `rules.run.isolate` | `TabsBloc._applyRules` | same, on a background isolate (body > 64 KiB) |
| `tabs.putTab` | `TabsBloc._flushDirtyTabs` | debounced incremental tab persistence |

## How to profile

```
fvm flutter run -d macos --profile
```

Open DevTools → **Performance**. Record while exercising each scenario, then
check the **UI** track for frames over budget (~16 ms) and the **Timeline
Events** for the spans above:

1. **Large response + chaining rules** — send a request returning a multi-MB
   JSON body with several jsonPath extraction/assertion rules. `rules.run.isolate`
   should appear off the UI track; the UI thread should not spike.
2. **High-rate stream** — connect an SSE/WebSocket source that emits rapidly.
   Frames coalesce (~1 emission per 16 ms window); the live panel should scroll
   without dropping frames.
3. **Cold start** — relaunch with real data (large `tabs.hive` / `history.hive`).
   Critical Hive boxes open in parallel; `cookies`/`requestRules` open after the
   first frame (`warmUpDeferredBoxes`).
4. **Rapid edits** — create/rename/move collections, edit environments, trigger
   `Set-Cookie` responses. Environments/cookies persist per-key (no whole-list
   rewrite); collections are debounced.
5. **Splitter drag + search typing** — dragging the split divider relayouts the
   panes without rebuilding the editors; search fields are debounced (~220 ms)
   and only the results list rebuilds.

If a scenario shows a UI-isolate stall, capture the offending Timeline span and
open an issue with the trace.

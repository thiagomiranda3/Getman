# Tabs & panels — the request/response editor

> Deep-dive for the tabs feature (request/response editor), tab panels (virtual-desktop workspaces), response time-travel, and dirty tracking. Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md.

The tabs feature is the most complex in the app. Its BLoC is panel-aware; its screen (`request_view.dart`, in `lib/features/tabs/presentation/screens/`) owns the code controllers and split.

## TabsBloc

- `TabsBloc` owns a private `_RequestManager` (`request_manager.dart`) mapping `tabId → NetworkCancelHandle`.
- **Debounced save**: any mutating event calls `_scheduleSave()` with a 10-second timer; `close()` cancels the timer, cancels in-flight requests, flushes a final `_persist()`.
- On `LoadTabs`, the BLoC sanitizes persisted tabs by resetting `isSending=false` — no real network call is alive after a restart.
- `_onRemoveTab` cancels the tab's handle before dropping the tab.
- `SendRequestUseCase` couples the network call with history persistence. History writes are best-effort: failures are caught and logged via `debugPrint` (never fail the request), but they are **not silent** — a regression in persistence shows up in console logs.

### Identity-based events

`RemoveTab`, `CancelRequest`, `CloseOtherTabs`, `CloseTabsToTheRight`, `DuplicateTab`, and `SendRequest` all carry `String tabId`, not `int index`. Handlers resolve the current position via `indexWhere`/`byId` and bail on miss. Only `SetActiveIndex` and `ReorderTabs` are position-based (position *is* the operation) — and `SetActiveIndex` rejects out-of-range indices so widgets may index `tabs[activeIndex]` safely. **Do not reintroduce index-based identity events** — they race against concurrent emissions. This applies to event payloads too: identity-addressed events carry `tabId`. Always look tabs up with `state.tabs.firstWhereOrNull((t) => t.tabId == id)`; never index by position across state emissions.

### Responses are a value object

`HttpRequestTabEntity.response` is an `HttpResponseEntity?` (`null` = nothing sent yet / last send cancelled). The Hive model (`HttpRequestTabModel`, typeId 2) still stores the four flat columns — `statusCode == null` is the discriminator on read. Don't re-flatten the entity.

### Cancellation flow

UI dispatches `CancelRequest(tabId)` → `_RequestManager.cancel(tabId)` → Dio throws `DioExceptionType.cancel` → mapped to `NetworkFailure(type: cancelled)` → BLoC clears `isSending` without recording a response. Any non-`NetworkFailure` error in the send path also resets `isSending` (catch-all) — a tab must never be stuck on SENDING.

## Response time-travel

Each successful/error send is prepended (newest-first) to `HttpRequestTabEntity.responseHistory` (`List<ResponseHistoryEntry>`), trimmed to `settings.responseHistoryLimit` in the bloc's `_recordResponse`. `response` stays the *displayed* response (defaults to the newest); `ViewResponseHistoryEntry(tabId, entryId)` swaps it to an older entry **without** mutating the history (all response views read `tab.response` unchanged).

Two independent size treatments apply — do not conflate them:

- **The `saveLargeResponsesInHistory: false` downgrade happens in `TabsBloc._recordResponse`.** It downgrades only *superseded* entries over `kLargeResponseViewerChars` to `kHistoryBodyNotKeptPlaceholder` at the next record. The **newest entry always keeps its full body** — it is what "Latest" restores after time-travelling. In-session entries otherwise keep full bodies.
- **The unconditional 1 MiB cap happens separately in `tabs_repository_impl._toPersistableModel`.** It caps the current response body *and* every `responseHistory` entry over `kMaxPersistedResponseBodyChars` (1 MiB) at persist time.

The metadata-row timeline is `ResponseHistoryTimeline` (hidden under 2 entries); earlier responses also appear in the Compare picker (`CompareTargetSource.timeline`).

## URL bar, cURL paste, request editor tabs

- The cURL paste shortcut: `_handleUrlChanged` in `url_bar.dart` treats URL input starting with `curl ` as a full request spec, runs it through `CurlUtils.parse`, and pushes a single `UpdateTab` with the parsed method/url/headers/body. Body is then prettified off the UI thread via `JsonUtils.prettify` (runs in `compute`).
- The PARAMS/HEADERS/BODY tab bodies live in `params_tab_view.dart` / `headers_tab_view.dart` / `body_tab_view.dart` (with `bulk_mode_toggle.dart` for the bulk key/value paste mode) and are composed by both the split-pane `RequestConfigSection` and the phone `UnifiedRequestPanel` — edit them once, both layouts follow.
- `_setControllerPreservingEnd` (in `url_bar.dart`) is the only safe way to push text into a `TextEditingController` without jumping the cursor during an echo-write.

## Response pane

The response pane is a shell (`response_section.dart` → `ResponseSection`) over per-tab views under `tabs/presentation/widgets/response/` (`ResponseBodyView` + private `_BodyModeToggle`, `ResponseHeadersView`, `ResponseCookiesView`, `ResponseTestsView`, `ResponseMetadataItem`, `ResponseHistoryTimeline`). `ResponseBodyView` carries Copy + Save-to-file (`saveJsonFileWithFeedback`, json/txt) over `_copyableText()` (the verbatim body incl. the large-body cache).

### Response body modes

`_BodyModeToggle` is a 3-segment PRETTY/RAW/TREE switch (keys `body_toggle_*`). TREE renders `JsonTreeView` (collapsible, virtualized) and is only enabled when the body decodes to a JSON object/array under `kLargeResponseViewerChars` (the decode is cached in `_decoded` so the tree keeps its expansion state across rebuilds). Each tree node offers Copy value, Copy path (a JSONPath built by `core/utils/json_path_builder.dart` in the exact grammar `JsonPath` accepts), and **Extract to `{{var}}`** → `ResponseBodyView._extractToVariable` dispatches `AddExtractionRule(configId, rule)` to the global `RulesBloc` (loads+appends+saves), closing the loop with the chaining engine.

## Panels (virtual-desktop workspaces for tabs)

`TabsBloc` is panel-aware. `TabsState` holds `List<PanelEntity> panels` + `String activePanelId` and exposes `tabs`/`activeIndex` as the **active panel's** view (recomputed via the private `_derive` helper on every emit) so all tab widgets keep reading `state.tabs`/`state.activeIndex` unchanged. `PanelEntity {id, name, List<HttpRequestTabEntity> tabs, activeTabId}`.

Invariant enforced in the bloc: always ≥1 panel (`RemovePanel` on the last is rejected). A panel **may be empty** (zero tabs) — closing/moving out its last tab, or `AddPanel` itself, leaves it empty with `activeTabId == ''`; the UI then shows the `EmptyTabsPlaceholder` ("NO OPEN TABS"), exactly like the pre-panels zero-tabs state. There is **no** auto-seed (the old `_ensureNonEmpty` floor was removed — don't reintroduce it).

Events: `AddPanel` / `RemovePanel` / `RenamePanel` / `SetActivePanel` / `ReorderPanels` / `MoveTabToPanel` / `MoveTabToNewPanel`. Active-panel-scoped tab events (`AddTab`, `SetActiveIndex`, reorder, close, duplicate) early-return when `panels` is empty (pre-`LoadTabs`); in-flight sends + `UpdateTab` resolve their tab **across all panels** (`_findTab`/`_replaceTabAcrossPanels`) so a request started in a non-active panel still lands in its tab.

Persistence: per-panel tab order = `PanelModel.orderedTabIds`; panels store only **ids** (tab entities stay in the `tabs` box, typeId 2). Panel order + active panel live in the `tabs_meta` box under keys `panelOrder` / `activePanelId`. `LoadTabs` wraps pre-panels installs into a single seeded `"Panel 1"` (legacy migration) and persists it.

UI: `PanelSelector` dropdown in the tab strip (desktop/tablet/phone) + folded into `TabSwitcherSheet` on compactPhone; moving tabs via the `MOVE TO PANEL ▸` tab context-submenu + long-press-drag onto the selector; the close-panel save flow is `closePanelWithSavePrompt` (widget-layer coordinator: discard-all vs review-and-save one-by-one) — call it with a context **below** `MaterialApp` (the root navigator's), since dismissing the selector overlay unmounts the row context. The tab strip is rendered by `MainScreen` (`_buildTabBar`) + `request_tab_chip.dart` (`RequestTabChip`).

Shortcuts: **Cmd/Ctrl+Shift+N** new panel, **+Shift+] / +Shift+[** next/prev panel, **+Shift+1–9** jump to panel N.

## Dirty tracking

`TabDirtyChecker` (`lib/features/home/domain/usecases/tab_dirty_checker.dart`) is registered as a lazy singleton and exposed to widgets via `RepositoryProvider`. Widgets read it with `context.read<TabDirtyChecker>()`. It is tab-centric:

- If the tab is linked to a collection node, compare `tab.config` with the saved node's config.
- Otherwise compare with the default `HttpRequestConfigEntity(id: tab.config.id)`.

Consumed by the tab close/save flows: `request_tab_chip.dart` (close / close-others confirms), `panel_close_coordinator.dart` (close-panel save prompt), and `request_view.dart` (SAVE-to-collection).

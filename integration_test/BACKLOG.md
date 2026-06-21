# E2E coverage backlog

Flows covered by the macOS `patrol_finders` suite (`run_macos.sh`). The 2026-06-16
"break-everything" pass took the suite from broad happy-path (~23 cases) to deep
dirty/edge-path coverage (~95 cases). What remains is genuinely blocked
(native dialogs) or low-value.

---

## Covered (deep)

- **Command palette** — `command_palette_test` + `command_palette_deep_test`
  (open via shortcut, filter, run; jump to a saved request / environment;
  arrow-key navigation).
- **Saved examples (M10)** — `saved_examples_test` (capture from the response
  pane, inline sub-row, open as an unlinked tab, rename, delete).
- **Drag-and-drop tree reorder** — `collections_deep_test` (re-parent a folder
  by drag) + `extras_test` (reorder tabs by drag).
- **Code-export reflects edits** — `code_export_edits_test` (edited URL +
  method + headers + a second target). Found & fixed the stale-config bug
  (url_bar captured `tab.config` at build time; now reads fresh at press time).
- **Environments — secrets & active-env deletion** — `environments_deep_test`
  (mark secret + reveal, delete the active env → "No Environment", dynamic
  vars, Cmd+E quick switcher, multi-env base-URL switch).
- **Tab management beyond open/close** — `tab_management_test` (duplicate /
  close-others / close-to-the-right / copy-URL / dirty `*`), `tab_shortcuts_test`
  (Cmd+N/W, Cmd+1–9, Ctrl+Tab, Cmd+Enter/S/L), `extras_test` (drag reorder).
  Found & fixed: saving a new request never linked the tab (dirty forever,
  duplicate-on-resave, save-as-example never enabled).
- **Responsive layout** — `responsive_test` (resize across every breakpoint and
  back, drawer nav, unified phone panel send, resize with a dialog open).
- **Error & edge states** — `error_states_test` (404/500, cancel in-flight,
  connection failure, malformed JSON, 204) + `settings_network_test`
  (history-limit trim, receive-timeout abort).
- **Settings tabs** — `settings_tabs_test` (four-tab dialog: navigate
  GENERAL/APPEARANCE/NETWORK/WORKSPACE on desktop + switch tabs at phone width).
- **Themes** — `theme_stress_test` (every theme in light + dark, compact, rapid
  glass↔flat switching, the LIQUID GLASS reduce-effects toggle-twice guard).
- **Theme motion during a send** — `theme_motion_send_test` (each "loud" theme —
  ARCANE QUEST / LIQUID GLASS / AURIS / DRACULA — drives a real send so the
  in-flight panel-frame motion mounts/disposes while a request is in flight,
  asserting the app survives + the 200 renders; plus a reduce-effects send that
  must still complete with motion degraded to static). E2E guard for the
  in-flight-frame dispose fix.
- **Chaining (deep)** — `chaining_deep_test` (JSONPath / header / contains
  assertions, mixed pass-count, extraction write-back into the active env).
- **Realtime (deep)** — `realtime_deep_test` (server-initiated WS broadcast,
  multiple WS messages, multi-event SSE).
- **Body types** — `body_types_test` (switch every type, urlencoded send,
  beautify button) + `request_config_deep_test` (bulk param/header editing).
- **Auth** — `auth_deep_test` (Basic, API-key in header + query).
- **History (deep)** — `history_deep_test` (search filter, re-send as a tab).
- **Response views (deep)** — `response_views_deep_test` (empty placeholder,
  copy, empty cookies, compare/diff).
- **Tab panels** — `panels_test` (24 flows): create via footer + Cmd+Shift+N;
  switch via dropdown row (remembered active tab) + next/prev/jump shortcuts;
  rename via double-tap, per-row pencil, inactive-row pencil, empty→`Panel N`
  reset; reorder rows (persist verified by reopening the dropdown); move tabs
  via the `MOVE TO PANEL` submenu + `NEW PANEL…` + drag-onto-selector (row /
  + New panel) + last-tab-out auto-seed; close clean (confirm), dirty Discard
  all, dirty Review & save (save unlinked → collection), Review→Cancel keeps
  panel, last-panel close blocked; last-tab-close auto-seed; per-panel active
  tab memory; in-flight send in Panel A lands while focused on Panel B (mock
  delay server); full restart persistence (names + order + active panel +
  per-panel active tab + dirty tab, via a manual same-dir double `di.init`);
  compact-phone `TabSwitcherSheet` (create / switch via chip) + resize back.

---

## Still not automated

### 1. Native file-dialog flows
- **Missing:** collection/environment import & export, binary & multipart-**file**
  body, response **Save to file**.
- **Why:** `patrol_finders` can't drive native macOS file pickers (Patrol native
  automation is unsupported on macOS desktop).
- **Suggested:** put the picker behind an injectable seam so tests feed a path,
  or run these on a mobile simulator with Patrol native.

### 2. Settings — mTLS / proxy / redirects / verify-SSL end-to-end
- **Missing:** client-certificate (mTLS), proxy routing, follow-redirects +
  max-redirects, verify-SSL toggle — all need a server that actually exercises
  the setting (TLS, redirect chains, a proxy).
- **Done already:** history-limit trim and receive-timeout are covered.

### 3. JSON editor internals (re_editor)
- **Missing:** typing into the body/response code editor, the find panel,
  fold/unfold interactions.
- **Why:** `re_editor` doesn't expose a standard `EditableText`, so
  `patrol_finders.enterText` can't drive it. Body is set via cURL-paste in tests
  instead; the fold gutter is asserted in `json_fold_test`.

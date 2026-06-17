# Tab Panels (virtual-desktop workspaces for tabs) — Design

**Date:** 2026-06-17
**Status:** Approved design, pre-implementation
**Feature dir:** `tabs` (extends the existing feature; no new top-level feature)

---

## 1. Problem & Goal

In Postman-style clients you accumulate request tabs you don't want to close yet
(you'd have to decide *now* whether to save or discard each one), but they clutter
the tabs you're actively working on. There's no way to set them aside *without
deciding their fate*.

**Goal:** add **panels** — virtual-desktop-style workspaces for tabs. The app has at
least one panel; the user can add, rename, reorder, and remove panels, and shift open
tabs between them at will. Only the **active panel's** tabs are shown in the tab strip
at any time (like OS virtual desktops). A panel can be closed all at once, with a flow
to either discard every tab or review-and-save them one by one. All panel + tab state
(including dirty tabs) survives an app restart unchanged.

### Confirmed product decisions

| Decision | Choice |
|---|---|
| Panel switcher UI | **Compact panel dropdown** at the left of the tab strip |
| Moving tabs between panels | **Both** a `MOVE TO PANEL ▸` menu *and* drag-onto-the-selector |
| Empty panels | **Not allowed** — every panel always has ≥1 tab |
| New empty panel (`+`) | Seeded with one blank `NEW REQUEST` tab |
| `Move to panel → New panel` | New panel contains *only* the moved tab (no seeded blank) |
| Renaming | Must be **easy/discoverable** — multiple affordances (§7) |
| Responsiveness | Must adapt across all four `LayoutMode` tiers (§8) |
| Persistence | Full state, dirty tabs included, restored on restart (§9) |

---

## 2. Architecture (Approach A — panel-aware `TabsBloc`)

`PanelEntity` becomes the unit `TabsBloc` manages. `TabsState` exposes the **active
panel's** tabs + active index exactly as today, so every existing tab widget
(`TabContentStack`, `TabWidget`, `RequestView`, send/close/reorder/duplicate paths, the
dirty checker) keeps working untouched — the panel layer only changes *which* tabs are
in view.

Rejected alternatives:
- **Separate `PanelsBloc` + `TabsBloc`** — switching panels would force `PanelsBloc → TabsBloc` coupling, which the project forbids; per-panel active-tab coordination across two blocs is fragile.
- **`panelId` on every tab** — changes the meaning of `state.tabs` (now all panels), forcing every consumer to filter, and needs a typeId-2 model migration. More churn, less safety.

---

## 3. Data Model

### 3.1 Domain entity — `PanelEntity`

New file `lib/features/tabs/domain/entities/panel_entity.dart`:

```
PanelEntity extends Equatable {
  String id;                          // UUID, generated in ctor if absent
  String name;                        // "Panel 1" by default, or user-set
  List<HttpRequestTabEntity> tabs;    // ordered; INVARIANT: length >= 1
  String activeTabId;                 // remembered active tab within this panel

  copyWith(...);                      // sentinel-based, like HttpRequestTabEntity
  props => [id, name, tabs, activeTabId];
}
```

Plus a `PanelListLookup` extension mirroring `HttpRequestTabLookup`:
`byId(id)`, and a helper to find the panel that *owns* a given `tabId`.

### 3.2 `TabsState` changes

```
TabsState extends Equatable {
  List<PanelEntity> panels;     // NEW — ordered; INVARIANT: length >= 1
  String activePanelId;         // NEW — always a valid panel id
  List<HttpRequestTabEntity> tabs;  // KEPT — = active panel's tabs (recomputed per emit)
  int activeIndex;                  // KEPT — index of active panel's activeTabId in tabs
  bool isLoading;
}
```

`tabs` / `activeIndex` are **stored** fields (recomputed and passed on every `emit` via
a private `_withPanels(...)` helper), *not* getters — this keeps list identity stable
per emit so existing `buildWhen` selectors behave identically. `props` includes
`panels`, `activePanelId`, `isLoading` (tabs/activeIndex are a pure function of those,
so they're omitted from `props` to keep equality minimal and correct).

Convenience getters: `activePanel` (the `PanelEntity` for `activePanelId`).

### 3.3 Hive model — `PanelModel` (typeId 12)

New file `lib/features/tabs/data/models/panel_model.dart`, new `panels` box:

```
@HiveType(typeId: 12)
PanelModel extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String name;
  @HiveField(2) List<String> orderedTabIds;   // order within the panel
  @HiveField(3) String activeTabId;
  // next free: 4
  toEntity(Map<String, HttpRequestTabEntity> tabsById)  // builds tabs from ids, skips missing
  fromEntity(PanelEntity)
}
```

`PanelModel` stores **only ids** — the tab entities live in the existing `tabs` box
(typeId 2, **untouched**, keyed by `tabId`). The CLAUDE.md typeId table gets a row for
12 and "next free" becomes 13.

### 3.4 Box & meta keys

- `HiveBoxes.panels` — new box-name constant, opened on the cold-start path in `injection_container.dart` (alongside `tabs`); adapter registered there.
- Meta (existing `tabsMeta` box): new keys `panelOrder` (`List<String>` of panel ids) and `activePanelId` (`String`). The legacy global `order` key is read once during migration, then retired.

---

## 4. Invariants (enforced in `TabsBloc`)

1. **≥1 panel always.** `RemovePanel` on the last remaining panel is a no-op (UI also hides/disables the affordance).
2. **≥1 tab per panel always.** If a panel would become empty (its last tab closed *or* moved out), it auto-seeds a fresh blank `NEW REQUEST` tab and makes it active.
3. **Exactly one active panel** (`activePanelId` always valid).
4. **Each panel has exactly one valid `activeTabId`** (points to a tab it owns). Switching panels restores the target panel's remembered active tab.
5. **`tabId` globally unique** (already UUID). Send/cancel/move resolve a tab across *all* panels by id.

---

## 5. Events & Behavior

### 5.1 New panel events

| Event | Behavior | Persists |
|---|---|---|
| `AddPanel` | New panel named `"Panel N"` (lowest unused index), seeded one blank tab, becomes active. | panel model + meta |
| `RemovePanel(panelId)` | Closes panel + all its tabs (cancels in-flight via `RequestManager`). Rejected if last panel. If it was active, switches to the previous (or next) panel. *Dirty-save prompting happens in the widget layer before this fires — §6.* | delete panel model + delete its tabs + meta |
| `RenamePanel(panelId, name)` | Sets `name`; empty string resets to default `"Panel N"`. | panel model |
| `SetActivePanel(panelId)` | Switches active panel; restores its `activeTabId`. | meta |
| `ReorderPanels(oldIndex, newIndex)` | Reorders `panels`. | meta |
| `MoveTabToPanel(tabId, targetPanelId)` | Removes tab from its current panel, appends to target. If source becomes empty → auto-seed blank (inv. 2). If the moved tab was the source's active tab → source picks a neighbor. Target's `activeTabId` is unchanged (the moved tab is appended, not activated — the target already had ≥1 tab). **Active panel does not change** — the tab silently leaves your view. | both panel models + meta |
| `MoveTabToNewPanel(tabId, {name})` | Creates a new panel containing *only* the moved tab (no seeded blank), removes it from source (auto-seed source if emptied). **Active panel does not change.** | new + source panel models + meta |

### 5.2 Existing tab events — now panel-scoped

- `AddTab`, `RemoveTab`, `SetActiveIndex`, `ReorderTabs`, `DuplicateTab`, `CloseOtherTabs`, `CloseTabsToTheLeft/Right` operate on the **active panel**. They resolve the target panel by `activePanelId`, mutate that panel's `tabs`/`activeTabId`, and re-derive `state.tabs`/`activeIndex`.
- `RemoveTab` honoring inv. 2: closing a panel's *last* tab auto-seeds a blank (the panel is never empty).
- `SetActiveIndex` now also writes the active panel's `activeTabId` and **persists the panel model** (so the remembered active tab survives restart and panel switches).
- `SendRequest`, `CancelRequest`, `ViewResponseHistoryEntry`, `UpdateTab` resolve their tab by `tabId` across **all** panels (a request started in one panel keeps running while you're in another; its result lands in the owning tab regardless of which panel is active).

### 5.3 Loading & migration (inside the existing `LoadTabs` — no boot rewiring)

`main.dart` still dispatches `LoadTabs`; the handler now reconstructs panels:

1. **`panels` box non-empty** → load all tab models (→ `tabsById`), load panel models, build each `PanelEntity` from its `orderedTabIds` (skipping ids with no tab), read `panelOrder` + `activePanelId` from meta (falling back to first panel if missing/invalid), sanitize `isSending=false` on every tab across every panel.
2. **`panels` box empty + existing tabs present** (upgrade path) → wrap all existing tabs + their saved `order` into one seeded **"Panel 1"** (active tab = first tab, matching today's reset-to-0 behavior); write `panelOrder` + `activePanelId`.
3. **`panels` box empty + no tabs** (true first run) → seed **"Panel 1"** containing the existing sample httpbin.org GET request.

---

## 6. Close-Panel Save Orchestration (widget-layer coordinator)

Triggered by a panel row's ✕ or a `CLOSE PANEL` action. It reads `TabDirtyChecker`
against `CollectionsBloc`'s saved configs (the same source the existing per-tab close
prompt uses) — so no bloc→bloc coupling; the coordinator is a widget with both blocs +
dialogs in scope (mirrors `EnvironmentsDialog._deleteEnvironment` and the current
close-tab confirmation).

1. **No dirty tabs** → `ConfirmDialog`: *"Close 'Panel 2' and its 3 tabs?"* → on confirm, dispatch `RemovePanel`.
2. **≥1 dirty tab** → summary dialog *"Panel 2 has 2 unsaved tabs."* with **[Discard all & close]** · **[Review & save…]** · **[Cancel]**:
   - **Discard all & close** → `RemovePanel`.
   - **Review & save…** → walk the dirty tabs **one by one**: per tab, *"Save changes to '\<title\>'?"* with **[Save]** · **[Discard]** · **[Cancel review]**.
     - *Save* — **linked** tab → update its collection node (reuse existing save-to-node path); **unlinked** tab → existing save-to-collection flow (`NamePromptDialog` + pick location).
     - *Discard* — skip.
     - *Cancel review* — abort the entire close; panel stays.
   - After every dirty tab is resolved → `RemovePanel` (clean tabs just close with it).

> Implementation note: locate and reuse the existing "save request" path (the `SaveRequestIntent` / Cmd+S flow and its save-to-collection dialog) rather than re-implementing save plumbing.

---

## 7. Renaming — easy & discoverable (multiple affordances)

All routes dispatch the single `RenamePanel` event; an empty submission resets to `"Panel N"`.

- **Double-click / double-tap the panel name** in the selector → `NamePromptDialog` prefilled with the current name (the fast path).
- **Pencil icon** on each row in the panel dropdown list.
- **`RENAME PANEL`** entry in the panel context affordances and the phone sheet.

---

## 8. UI & Responsiveness

`LayoutMode` tiers (from `lib/core/theme/responsive.dart`): `compactPhone ≤500`,
`phone ≤700`, `tablet ≤900`, `desktop >900`. The horizontal tab strip exists for
phone/tablet/desktop; `compactPhone` collapses to `TabChip` + `TabSwitcherSheet`
(`context.useTabSwitcher`).

### 8.1 `PanelSelector` (new widget, `tabs/presentation/widgets/`)

- **desktop & tablet (>500):** dropdown at the **left of the tab strip**, before the tab list — active panel name + chevron, full name ellipsized past a max width so it never crowds the tabs / `AddTabButton` / `EnvironmentSelector`.
- **phone (501–700):** same strip, selector rendered **compact** (panels icon + short/ellipsized name) to preserve room for tabs.
- Tapping opens an overlay menu: every panel as a **reorderable row** (`name` · tab-count · active-check · pencil · ✕), plus a **`+ New panel`** footer.
  - Row tap → `SetActivePanel`. Pencil → rename. ✕ → close-panel orchestration (§6). Drag rows → `ReorderPanels`. Footer → `AddPanel`.
- Selector button is a `DragTarget<String>` for a `tabId`: dragging a tab over it pops the panel list as drop targets — drop on a row → `MoveTabToPanel`, drop on `+ New panel` → `MoveTabToNewPanel`. (Reuses the `Draggable<String>` already on tabs.)

### 8.2 Tab context menu / action sheet

Add a `MOVE TO PANEL ▸` submenu listing the **other** panels + `New panel…` →
`MoveTabToPanel` / `MoveTabToNewPanel`, in both the desktop `TabWidget` right-click menu
and the phone tab action sheet.

### 8.3 compactPhone (`TabSwitcherSheet`)

Panels fold into the sheet: a panel-chip row (+ `New panel`) at the top, active panel's
tabs below, double-tap/pencil to rename a chip, `Move to panel ▸` per tab. The collapsed
`TabChip` label shows the active panel (e.g. *"Panel 2 · 2/5"*).

All sizing/colors/weights/radii pull from `context.appLayout` / `appPalette` / `appShape`
/ `appTypography` / `appDecoration`; layout branches use the existing
`ResponsiveBuildContext` getters (add a getter only if a genuinely new branch is needed).
No hardcoded sizes/colors/breakpoints in widgets.

---

## 9. Persistence

| What | When it writes |
|---|---|
| Tab content (`tabs` box, keyed by `tabId`) | debounced 10 s `putTab` (unchanged); holds every tab across every panel |
| `PanelModel` (`panels` box, keyed by `panelId`) | immediately on add/remove/rename/reorder/move, and on `SetActiveIndex` (active-tab change) |
| Meta `panelOrder` + `activePanelId` | immediately on add/remove/reorder/switch-active |
| Final flush | `close()` flushes dirty tabs + all panel models + meta |

Panel-structure writes are immediate (cheap id/name metadata, no response bodies). Tab
*content* edits stay on the existing debounce. Restart restores every panel, name, order,
active panel, and per-panel active tab — **dirty tabs included** (a dirty tab is just a
tab whose config differs from its saved node; nothing special needed — it persists like
any tab).

New repository methods (abstract `TabsRepository` + impl + local data source):
`getPanels()`, `putPanel(PanelEntity)`, `deletePanels(List<String> panelIds)` (also
deletes the panels' tabs from the `tabs` box), `savePanelMeta(order, activePanelId)`.

---

## 10. Keyboard Shortcuts (additive)

- **Ctrl/Cmd+Shift+N** → new panel.
- **Ctrl/Cmd+Shift+] / [** → next / previous panel.
- **Ctrl/Cmd+Shift+1–9** → jump to panel N (parallel to Cmd+1–9 = jump to tab N).

New intents (`NewPanelIntent`, `NextPanelIntent`/`PrevPanelIntent`, `JumpToPanelIntent`)
live at `MainScreen` (they need panel state), wired into the computed `appShortcuts` map
in `main.dart` (digit loop like the existing tab-jump bindings).

---

## 11. Testing — unit & widget (the done-bar)

- **Bloc tests:** add/remove/rename/reorder/switch panel; move tab (source+target order, active fixups, auto-seed on emptied source); `MoveTabToNewPanel` (target has only the tab, source auto-seeds if emptied); last-panel removal rejected; last-tab-in-panel auto-seed; `SetActiveIndex` persists `activeTabId`; send/cancel/update by id resolve across panels; in-flight request in a non-active panel completes into its owning tab.
- **Migration tests:** empty panels box + existing tabs → "Panel 1" wrapping them in saved order; fresh install → seeded sample in "Panel 1"; round-trip reload preserves names/order/active-panel/active-tab; reconstruction skips missing tab ids.
- **Repo / data-source tests:** `putPanel` / `deletePanels` (also drops the panel's tabs); `savePanelMeta` order + active; `getPanels` reconstruction.
- **Widget tests:** selector switch; double-click rename + pencil rename + reset-to-default on empty; both move methods (menu submenu + drag-onto-selector incl. drop-on-new-panel); close-panel confirm (no dirty); review-and-save orchestration (save linked / save unlinked / discard / cancel review); responsive selector (compact vs full) and the compactPhone sheet panel row.

Full gate before "done": `fvm flutter analyze`, `fvm dart run custom_lint`,
`fvm dart run bloc_tools:bloc lint lib`, `fvm dart format`, `fvm flutter test` all green;
Hive regen (`build_runner`) after the typeId-12 add.

---

## 12. Integration Tests (patrol_finders, macOS) — every interaction path

Added to `integration_test/` alongside the existing suite (and tracked in
`integration_test/BACKLOG.md`). Each flow drives the real app and asserts observable
state. Coverage must include **all** the ways a user interacts with panels:

**Creating & switching**
1. New panel via the `+ New panel` footer in the selector dropdown → it becomes active, shows one blank `NEW REQUEST` tab.
2. New panel via **Ctrl/Cmd+Shift+N** shortcut.
3. Switch panels by selecting a row in the dropdown → tab strip swaps to that panel's tabs; the panel's remembered active tab is restored.
4. Switch panels via **next/prev** shortcut and via **jump-to-panel-N** shortcut.

**Renaming (every affordance)**
5. Double-click the selector name → rename → label updates.
6. Pencil in a dropdown row → rename.
7. `RENAME PANEL` menu entry → rename.
8. Submit empty name → resets to `"Panel N"`.

**Reordering**
9. Drag panel rows in the dropdown to reorder → order persists.

**Moving tabs (both methods + new-panel)**
10. `MOVE TO PANEL ▸` submenu → move a tab to another panel; assert it left the source and appears in the target.
11. `MOVE TO PANEL ▸ New panel…` → a new panel is created containing only that tab; active panel unchanged.
12. Drag a tab onto the `PanelSelector` → drop on a panel row (`MoveTabToPanel`).
13. Drag a tab onto the selector → drop on `+ New panel` (`MoveTabToNewPanel`).
14. Move the **last** tab out of a panel → source auto-seeds a blank tab (never empty).

**Closing panels (the full save flow)**
15. Close a panel with **no dirty tabs** → confirm → panel + tabs gone.
16. Close a panel with dirty tabs → **Discard all & close**.
17. Close a panel with dirty tabs → **Review & save** → save a **linked** tab (updates node), save an **unlinked** tab (save-to-collection), **discard** another → panel closes after all resolved.
18. Close a panel with dirty tabs → Review & save → **Cancel review** → panel stays intact.
19. Attempt to close the **last** panel → blocked (no-op / affordance disabled).

**Auto-seed & active-tab memory**
20. Close a panel's last tab (not via panel close) → auto-seeds a blank tab.
21. Per-panel active tab is remembered across switches.

**In-flight requests across panels**
22. Start a request in Panel A, switch to Panel B, switch back → response is present in the originating tab.

**Persistence across restart**
23. Build several panels (custom names, custom order, specific active panel + per-panel active tabs, at least one dirty tab), restart the app → exact state restored, dirty tab still dirty.

**Responsiveness**
24. Resize to `compactPhone` → tab strip collapses; panel UI is reachable in the `TabSwitcherSheet` (create / switch / rename / move). Resize back → horizontal strip + selector return.

All integration flows green (on top of the unit/widget gate) **before** the wiki step.

---

## 13. Documentation (wiki — after integration tests)

Per the CLAUDE.md sync mandate, in the separate `Getman.wiki.git` repo:
- New **Panels** page documenting: what panels are, the selector dropdown, add/rename
  (all affordances)/reorder/remove, moving tabs (menu + drag), the close-panel discard /
  review-and-save flow, the ≥1-tab rule, persistence, and the new keyboard shortcuts.
- Add the page to `_Sidebar.md`.
- Update any shortcuts page with the three new bindings.
- Use verbatim UI labels.

---

## 14. Out of Scope (YAGNI)

- Viewing two panels at once / split-screen (panels are one-at-a-time, like virtual desktops).
- Per-panel environments or settings (the active environment stays global).
- Drag-reordering tabs *across* panels by dragging within the strip (moving is via menu / drop-on-selector).
- Exporting/sharing panels, or panels in the git workspace mirror / Postman export.
- Nested panels / panel groups.

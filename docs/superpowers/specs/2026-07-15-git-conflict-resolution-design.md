# Spec D — Semantic Conflict Resolution (design)

**Status:** approved 2026-07-15. Branch `feat/git-conflict-resolution` (off Spec
C's `feat/git-pr-integration`). Fourth and final spec in the
git-native-collaboration roadmap (A = review & commit / PR #50; B = branch &
sync / PR #51; C = PR integration / PR #52).

## Goal

Resolve `git pull --rebase` merge conflicts **inside Getman**, field-by-field,
on the diff-friendly collections workspace — turning git's whole-file conflict
into a semantic, per-field merge where non-overlapping edits merge silently. Plus
keep the remote view fresh with **auto-fetch** and a manual **FETCH** action.
Built on Spec A's diff engine and Spec B's pull/mirror plumbing. Desktop-only,
web-gated, **no credentials stored**.

## Why

Today `BranchService.pull` runs `git pull --rebase` and, on any conflict, runs
`git rebase --abort` and throws — the user is bounced to their own git tool. But
the workspace is a clean per-request/per-folder JSON tree, so most "conflicts"
are edits to *different fields* of the same request and can merge automatically;
only true field overlaps need a human. That semantic merge is the
differentiator. Auto-fetch closes the loop: you can't decide to pull until you
know you're behind, and git only learns that on a fetch.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Entry flow | **Pause & resolve inline** | `pull` stops aborting; on conflict it leaves the rebase paused, opens the resolver, and (on resolve) `git add` + `rebase --continue`, looping per commit. Cancel → `rebase --abort` (today's behavior). Most seamless. |
| Conflict scope | **Field-level for req + folder; file-level for structural** | Both diff functions already exist; structural (add/add, delete/modify, manifest) get a coarse keep-mine/keep-theirs; unmodelable → abort with a clear message. |
| Merge model | **3-way auto-merge, prompt only on true overlaps** | Read base/ours/theirs (`git show :1/:2/:3`); a field only one side changed auto-merges silently; only both-changed-to-different-values prompts. |
| 3 versions | **`git show :N:path` per stage**, not conflict-marker parsing | JSON with `<<<<<<<` markers is unparseable; the index stages are clean JSON. |
| Rebase ours/theirs | **Label by user's mental model** | In a rebase `:2` is upstream, `:3` is your replayed commit — the opposite of a merge. UI says **Incoming** (remote) vs **Yours** (local); never raw ours/theirs. |
| Fetch | **Auto (timer + on-connect) + manual FETCH action** | Keeps ahead/behind accurate. `git fetch` only — never touches the working tree; collections change only on an explicit PULL. |
| Credentials | **None stored**, git config never edited | Same guarantee as A/B/C. |
| Platform | **Desktop only** (web-stubbed + `kIsWeb`) | git is a desktop binary. |

## Architecture (three layers, mirroring A/B/C)

### Core — `lib/core/git/`
Extend `GitService` (the sole `dart:io` boundary; web-stubbed) with conflict +
fetch primitives:

- `Future<bool> isRebaseInProgress(String root)` — `.git/rebase-merge` /
  `rebase-apply` present (via `git status` porcelain v2 / rev-parse).
- `Future<List<String>> conflictedPaths(String root)` —
  `git diff --name-only --diff-filter=U`.
- `Future<String?> showStage(String root, String path, int stage)` —
  `git show :<stage>:<path>`; null when the stage is absent (add/add has no `:1`).
- `Future<void> add(String root, String path)` / `rebaseContinue` /
  `rebaseAbort` — `git add <path>` / `git rebase --continue|--abort`.
- `Future<void> fetch(String root)` — `git fetch`; updates remote-tracking refs
  only.

`pull` changes: on a non-zero `git pull --rebase`, if a rebase is in progress
with conflicted paths, **return a "conflicted" result** instead of aborting +
throwing; a non-zero pull with *no* conflicts still `rebase --abort`s and throws
`GitException` (unchanged for auth/network/other failures).

### Domain — `lib/features/collections/`
- `logic/three_way_merge.dart` — **pure Dart** `ThreeWayMerge` engine. Input:
  `base`/`incoming`/`yours` entities (any may be null). Output: the auto-merged
  fields + a list of unresolved `FieldConflict`s (field label, kind, the two
  candidate values, an `isOpaque` flag for auth). Reuses the field vocabulary of
  Spec A's `RequestConfigDiff` / `FolderNodeDiff`.
- `conflict_service.dart` — abstract `ConflictService`: `pullOrConflict(root)`,
  `currentConflicts(root)` → `List<FileConflict>`, `resolve(root, resolutions)`
  (write merged files + `git add`), `continueRebase(root)` →
  `RebaseStep {done | moreConflicts}`, `abort(root)`, `fetch(root)`.
- Entities: `FileConflict {path, ConflictKind kind, NodeConflict? fields}` where
  `ConflictKind ∈ {request, folder, addAdd, deleteModify, structural}`;
  `NodeConflict {List<FieldConflict>, autoMerged entity}`; a resolution is a map
  of field → chosen side (or an edited value) plus, for structural, a whole-file
  side.

### Data — `lib/features/collections/data/services/`
`GitConflictService implements ConflictService`, composing `GitService` (stage
reads/writes, rebase control, fetch) + the existing `WorkspaceCollectionSerializer`
(JSON ↔ entity). Classifies each conflicted path by extension + which stages
exist; parses stages to entities; runs `ThreeWayMerge`; on `resolve`, applies the
picks, serializes the merged node, writes it, and `git add`s it. A path whose any
stage fails to parse degrades to a **structural** (file-level) choice — never a
forced entity write.

### Presentation — `lib/features/collections/presentation/`
- `bloc/conflict_bloc.dart` (+ event/state) — on the `ConflictService`
  abstraction only. Drives the resolve→`--continue`→(next batch | done) loop;
  droppable-while-busy; a terminal state on every path. State carries the current
  batch of `FileConflict`s, the user's in-progress resolutions, and a
  commit-progress hint.
- `widgets/conflict_resolution_dialog.dart` — one row per conflicted file
  (tagged by kind). Field-level files expand to conflicting-field rows, each with
  **Take Incoming / Keep Yours / Edit** (auth/form: the two coarse choices only;
  `body`: the JSON code editor). Structural files show **Take Incoming / Keep
  Yours**. A file with zero true conflicts shows as **auto-merged** (no action).
  Header shows "commit N of M". **RESOLVE & CONTINUE** is enabled only when every
  conflict has a pick; **CANCEL** aborts the rebase.

## Field granularity (the merge engine)

Per field, given `base`/`incoming`/`yours`:
- `incoming == yours` → take it (agreement).
- exactly one side differs from `base` → **auto-merge** that side, silently.
- both differ from `base` to different values → **true conflict**, surfaced.

- **Scalars** (`method`, `url`, `bodyType`, `body`, `bodyFilePath`,
  `graphqlVariables`; folder `name`, `favorite`) — one row; Take Incoming / Keep
  Yours / Edit (prefill from either side; `body` uses the JSON editor).
- **Maps** (`headers`, folder `variables`) — resolved **per key**: different keys
  auto-merge; same-key/different-value collides.
- **Auth** — secret/opaque: whole-block Take Incoming / Keep Yours, no values, no
  editor.
- **Form fields** — list: whole-field Take Incoming / Keep Yours (no per-item
  merge in v1 — YAGNI).

A file with no surviving true conflict **auto-resolves and stages with no
prompt** — the payoff: a git "conflict" that is really two non-overlapping edits
merges silently.

## Structural conflicts (file granularity)

- **add/add** (both created the path, no `:1`) — Take Incoming / Keep Yours (may
  still be shown field-level with base=empty since both stages parse).
- **delete/modify** — framed plainly: **"Keep your edited request"** vs
  **"Accept the deletion."**
- **`workspace.json` manifest / any unparseable stage** — Take Incoming / Keep
  Yours at file level.

## Auto-fetch + manual fetch

- `GitService.fetch` / `BranchService.fetch` / `GitSyncBloc.FetchRemote(root)` —
  `git fetch` then reload branch status so the chip's ahead/behind refreshes.
  Never changes the working tree.
- **Auto**: a widget-layer coordinator in `BranchChip`'s State (alongside the
  existing mirror listener) fetches on workspace-connect and on a periodic timer
  (a small constant, ~5 min) while a workspace **with a remote** is connected.
  Failures are logged, not shown (offline is normal). **No auto-pull.**
- **Manual**: a **FETCH** item in the branch-chip menu (disabled as
  **FETCH — NO REMOTE** without an upstream) → `FetchRemote`; manual failures
  surface in a **GIT ERROR** dialog.
- Interval is a constant, not a setting, in v1 (YAGNI).

## Flows

**Pull with conflicts:** PULL → `pullOrConflict` → conflicted → dialog with the
first commit's `FileConflict`s → user picks → RESOLVE & CONTINUE → write + `add`
+ `rebase --continue` → more conflicts? loop : done → `BranchSyncListener`
reloads Hive from disk. CANCEL → `rebase --abort` → pre-pull state.

**Fetch:** timer/menu → `fetch` → reload status → chip ahead/behind refreshes.

## Error handling

- Non-zero pull with **no** conflicted paths → `GitException` (unchanged).
- `rebase --continue` failing (empty commit, hook) → **GIT ERROR** dialog; leave
  the repo paused (don't auto-abort the user's partial resolution).
- Resolved files are written through `WorkspaceCollectionSerializer` (the mirror
  writer), so a resolved file is byte-identical to a normal Getman write — no
  formatting drift that re-conflicts.
- The Spec B **mirror-suspension gate** is held across the whole
  resolve→continue→reload sequence so a debounced Hive→disk mirror can't clobber
  the resolution mid-flight.
- No credentials stored; git config never edited; all git calls in `*_io.dart`;
  web stub reports no rebase / no conflicts / fetch no-op.

## Testing

- **`ThreeWayMerge` (pure, the bulk):** non-overlapping fields auto-merge;
  true-overlap detection; per-key map merge (different keys silent; same-key diff
  collides); auth/form whole-field conflicts; base-absent (add/add); a
  zero-true-conflict file → fully merged entity, no prompts; unparseable stage →
  structural fallback.
- **`GitConflictService`** with a mock `GitService`: stage reads → entities;
  merged entity → serialize → `add`; classification (req/folder/structural).
- **`ConflictBloc`:** resolve→continue loop incl. multi-batch; cancel→abort;
  `--continue` failure surfacing; **non-vacuous** Completer-gated test that the
  next batch loads only after `--continue` (per the Spec B lesson).
- **`ConflictResolutionDialog`:** field rows (Take Incoming / Keep Yours / Edit);
  structural rows; auto-merged rows; commit-progress; blocs built inside the test
  body with a theme.
- **Fetch:** `GitSyncBloc.FetchRemote` reloads status; manual failure → error;
  auto-fetch timer coordinator (fake timer) fetches on connect + interval and
  swallows offline failures.
- **Real-git integration** (skips when `git` absent, like existing `GitService`
  tests): script a genuine conflicting rebase in a temp repo; assert stage reads
  and a full resolve→continue completes; a genuine fetch updates behind-count.
- Full done-bar: analyze, custom_lint, bloc_lint, fixtures self-test, format,
  100% tests.

## Out of scope (v1)

Per-item form-field merge; merge (non-rebase) conflict resolution; conflicts the
user started in their own CLI outside a Getman pull (the resolver engages from
Getman's pull flow); a configurable fetch interval; three-way merge of the
`workspace.json` manifest beyond file-level; auto-pull.

## Hazards / notes

- **Rebase ours/theirs are swapped** vs a merge — the engine and UI must read
  `:2` as Incoming and `:3` as Yours. This is the single most error-prone detail;
  it gets its own focused tests.
- **Non-interactive git**: all calls via `Process.run` with stdin closed (as in
  A/B/C); a `rebase --continue` that would open an editor is prevented with
  `GIT_EDITOR=true` / `--no-edit` semantics.
- **Wiki:** the Version Control page gains a "Resolving conflicts" section and a
  "Fetch" note — part of the final task.

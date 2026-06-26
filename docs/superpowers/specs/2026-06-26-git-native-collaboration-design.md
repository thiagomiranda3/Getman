# Git-Native Collaboration — Design (Spec 1 of 4: Review & Commit)

**Date:** 2026-06-26
**Status:** Approved (design); implementation pending
**Branch:** `feat/git-review-commit`

## The initiative & roadmap

Differentiate Getman from Postman by making **git-native collaboration** a
first-class, in-app experience — no cloud account, no proprietary workspaces.
Getman already mirrors collections to a clean, diff-friendly on-disk tree
(`.getman/workspace.json` manifest + per-folder `.folder.json` + per-request
`*.req.json`, ordered, with orphan reconciliation) and can reload disk → Hive.
This initiative builds the git *workflow* on top of that format.

It ships as **four sequenced specs**, in dependency order, all sharing the
`GitService` foundation introduced here:

1. **Spec 1 — A: Review & commit** (this document) — drive `git` on the
   workspace, show a semantic request-level diff of working changes, stage
   selectively, and commit in-app.
2. **Spec 2 — B: Branch & sync** — list/switch branches (switch → reload
   collections), pull, push.
3. **Spec 3 — C: PR / GitHub integration** — open a PR from the app (gh/API),
   link the review.
4. **Spec 4 — D: Semantic conflict resolution** — resolve merge conflicts in
   `*.req.json` field-by-field.

B depends on A; C on A+B; D builds on A's diff engine. Each gets its own
design → plan → implementation cycle. **This spec covers only A.**

## Summary (Spec A)

Turn the workspace directory into a git repo Getman drives, and add a
**Review changes** dialog: see what changed in your collections since the last
commit as a **semantic, request-level diff**, **stage individual requests/
folders**, and **commit** with a message — all in-app. Desktop-only
(web-gated).

## Why this approach

Shell out to the **system `git` CLI** via `dart:io` Process, gated for web with
a conditional import + stub exactly like the auto-updater
(`update_gate.dart`/`_io`/`_stub`). **git's own index is the staging source of
truth** (`git add` / `git reset`), so there is no app-side staging state to
desync, and the later specs (B/C/D) become straightforward additional CLI
calls.

Rejected alternatives:
- **Pure-Dart git library** — current libraries are immature and would
  reimplement a lot; high risk for little gain on desktop where `git` exists.
- **App-managed snapshots** (Getman's own history, no git) — defeats the entire
  point: the differentiator is interop with real branches/PRs/review in the
  user's existing git workflow.

## Architecture

### 1. `GitService` — `lib/core/git/` (web-gated)

A thin wrapper over the `git` CLI, the sole owner of Process calls. Conditional
export: `git_service.dart` (interface + conditional export),
`git_service_io.dart` (native; the only importer of `dart:io`),
`git_service_stub.dart` (web no-op → reports unavailable). Mirrors the updater
gate pattern so web builds stay clean.

API (Spec A subset; B/C/D extend it later):
- `Future<bool> isAvailable()` — is `git` on PATH (e.g. `git --version`).
- `Future<bool> isRepo(String root)` — `git rev-parse --is-inside-work-tree`.
- `Future<void> init(String root)` — `git init`.
- `Future<String?> currentBranch(String root)` — `git branch --show-current`
  (null when no commits yet / detached).
- `Future<List<GitStatusEntry>> status(String root)` — parse
  `git status --porcelain=v1 -z`; each entry = `{path, indexStatus,
  worktreeStatus, renamedFrom}`.
- `Future<String?> headFile(String root, String path)` — `git show HEAD:path`
  (null if the file does not exist at HEAD, i.e. added).
- `Future<void> stage(String root, List<String> paths)` — `git add -- <paths>`.
- `Future<void> unstage(String root, List<String> paths)` —
  `git reset -q HEAD -- <paths>` (or `git rm --cached` for never-committed
  files; handled by the service).
- `Future<void> commit(String root, String message)` — `git commit -m`.

Failures surface as a typed `GitException(message, {command, exitCode})`.
Commands run with the workspace as CWD; no global git config is modified.

### 2. Domain — semantic diff (pure Dart, unit-tested)

- `RequestConfigDiff.diff(old, new) → RequestDiff` where `old`/`new` are
  `HttpRequestConfigEntity?` (null = added/deleted). `RequestDiff` is a list of
  `FieldChange { field, ChangeKind (added/removed/changed), before?, after? }`
  covering: `method`, `url`, query `params` (per-key add/remove/change),
  `headers` (per-key add/remove/change), `bodyType`, `body` (line diff via the
  existing `line_diff.dart`), `auth`, `kind`. Field-level, order-independent for
  maps.
- `FolderDiff.diff(old, new)` — `name`, `description`, and child **order**
  changes.
- These are pure functions on entities — no git, no Flutter, no IO.

### 3. `WorkspaceReviewService` — composes git + serializer

`Future<List<ReviewEntry>> review(String root)`:
1. `GitService.status(root)` → changed file paths.
2. Map each path → a collection node via the serializer's layout:
   `*.req.json` → request, `<dir>/.folder.json` → folder,
   `.getman/workspace.json` → "workspace order" entry.
3. For each, parse the HEAD version (`headFile` → JSON → `requestFromJson` /
   `folderFromJson`) and the working version, then compute the semantic diff.
4. Return `ReviewEntry { path, nodeKind, changeType, displayName, staged,
   diff }` (`staged` derived from the porcelain index column).

A standalone manifest/`.folder.json` order change surfaces as its own entry
("Folder order changed" / "Workspace order changed"), so reordering is a
reviewable, separately-stageable change.

### 4. `ReviewBloc` (bloc-over-service)

Events: `LoadReview`, `StageNode(path)`, `UnstageNode(path)`, `Commit(message)`,
`InitRepo`. State: `status` (loading / ready / committing / error),
`gitAvailable`, `repoExists`, `branch`, `entries`, `selectedPath`,
`errorMessage`. Staging/commit re-run `LoadReview` to resync from the index
(git is the source of truth). Logs via `dart:developer` `log(name: 'ReviewBloc')`.

### 5. UI

- **Trigger:** a **Review changes (N)** button in the collections panel header,
  badged with the change count, shown only when a workspace path is configured
  and on desktop (hidden on web / when no workspace).
- **`ReviewChangesDialog`** (`ResponsiveDialog`):
  - **Left:** the list of changed nodes — change-type icon (added/modified/
    deleted/renamed), name, path, and a **stage checkbox** per entry.
  - **Right:** the selected entry's **semantic diff** — a `RequestDiffView`
    rendering each `FieldChange` with add/remove/change coloring from
    `AppPalette`, reusing `line_diff.dart` for the body. Folder/order entries
    render their own compact diff.
  - **Bottom:** a commit-message field + **Commit** button (enabled only when
    ≥1 entry is staged and the message is non-empty).
  - **Empty / edge states:** "git not found" (with a hint to install git);
    "Not a git repo — Initialize git here" (runs `init`); "No changes."
- All sizes/colors/weights via the `context.app*` theme extensions; no
  hardcoded values; no `Colors.*` literals outside theme. No `GetIt` in widgets.

## Boundaries (Spec A)

- Operations: **init, status, diff, stage, unstage, commit** only. No push,
  pull, branch-switch, checkout, or merge (Spec B/D).
- **Collections only** (matches the existing mirror). Environments are not
  versioned here (future).
- **Desktop only.** The web build hides the feature and uses the `GitService`
  stub.
- Getman does not modify the user's global git config or author identity; it
  uses whatever git is configured in that repo/environment.

## Testing

- `GitService` (io) integration tests against a **temp git repo**: `init`,
  `status` parsing (added/modified/deleted/renamed), `headFile`, `stage`/
  `unstage`, `commit`. Skipped where `git` is unavailable.
- `RequestConfigDiff` / `FolderDiff`: pure unit tests across field cases
  (method/url/header add-remove-change/body/auth/bodyType/kind; added; deleted).
- Path → node mapping: unit tests against the serializer's slug layout.
- `WorkspaceReviewService`: unit tests with a fake `GitService` + in-memory
  files.
- `ReviewBloc`: `bloc_test` with a fake `GitService`/service (load → stage →
  commit; init; git-unavailable; error paths).
- `ReviewChangesDialog`: widget smoke + no-overflow guard; commit button
  enable/disable logic.

## Docs

A wiki page (e.g. **Version Control**) covering: set a workspace → Review
changes → stage → commit, plus the desktop-only / git-required note. Published
when the feature merges (per the keep-the-wiki-in-sync mandate). The page will
grow as B/C/D land.

## Deliberately deferred (later specs / out of scope)

- Push, pull, fetch, branch list/switch, checkout (Spec B).
- PR creation / GitHub integration (Spec C).
- Merge-conflict resolution UI (Spec D).
- Versioning environments alongside collections.
- A file watcher / auto-detect of external git changes (manual reload remains).

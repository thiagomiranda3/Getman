# Git-native collaboration (review, branches, PRs, conflicts)

> Deep-dive for the git-sync feature (in-app git review/commit, branch & sync, GitHub pull requests, and semantic conflict resolution). Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md. The underlying collections mirror is in docs/architecture/collections.md.

## What it does

Getman differentiates from Postman by making **git-native collaboration** a first-class, in-app experience — no cloud account, no proprietary workspace. Getman drives the system `git` CLI (and, for GitHub, the `gh` CLI) over the on-disk **workspace mirror** of your collections. It ships as four capabilities, built in dependency order on a shared `GitService` foundation:

- **A — Review & commit:** see a semantic, request-level diff of working changes, stage individual requests/folders, and commit in-app.
- **B — Branch & sync:** list/switch branches (a switch reloads the collections), pull (`--rebase --autostash`), push, stash, add a remote, fetch.
- **C — PR / GitHub integration:** open a pull request from the app and list open PRs (via `gh`).
- **D — Semantic conflict resolution:** resolve merge conflicts in `*.req.json` / `*.folder.json` field-by-field over a paused rebase.

Desktop-only (web-gated). Getman stores no credentials — `git` uses the OS git; `gh` rides on the user's existing `gh auth`.

## The workspace format

The feature builds on the diff-friendly on-disk mirror written by `WorkspaceSyncService` (see docs/architecture/collections.md): a `.getman/workspace.json` manifest + one `.folder.json` per folder + one `*.req.json` per request, with a stable field order and orphan reconciliation. Response-cache fields and saved examples are curated out on purpose. Hive stays the in-session source of truth; disk is reloaded → Hive after a git op changes files.

## Components & where things live

**Core CLI gateways (`lib/core/git/`)** — the only process boundaries:

- `git_service.dart` — abstract `GitService` (status/stage/commit/branch/push/pull/stash + the paused-rebase conflict flow). Also declares `GitStatusEntry`, `GitException` (+ `isMissingIdentity`), `AheadBehind`, `StashEntry`, `PullOutcome`. Conditional export → `git_service_io.dart` (the sole `dart:io`/`git`-process importer) or `git_service_stub.dart` (web no-op).
- `gh_service.dart` — abstract `GhService` (`gh` CLI: PR list/create, auth status, default branch). Conditional export → `gh_service_io.dart` / `gh_service_stub.dart`. Declares `PullRequestInfo`, `GhException`.
- `gh_output_parser.dart` — pure parsing helpers: `rollupChecks` (reduces `statusCheckRollup` to none/pending/passing/failing; pending beats failing beats passing), `parsePrList` (tolerates wrong-typed fields), `parsePrUrl`.

**Domain gateways (abstract, `lib/features/collections/domain/`)** — what the blocs depend on: `branch_service.dart`, `conflict_service.dart`, `pull_request_service.dart`, `review_service.dart`.

**Data services (`lib/features/collections/data/services/`)** — compose the CLI gateways + the mirror:

- `git_branch_service.dart` (`BranchService`) — switch/create/push/pull/stash/addRemote/fetch. Pure of `dart:io`.
- `workspace_review_service.dart` (`ReviewService`) — builds the Review change set by diffing `git status` against the serializer (one `SemanticDiff` per file).
- `git_conflict_service.dart` (`ConflictService`) — classifies conflicted paths and 3-way merges request/folder JSON via `ThreeWayMerge`.
- `gh_pull_request_service.dart` (`PullRequestService`) — availability, list, create (composes `GhService` + `BranchService` so the pre-create push reuses the flush-guarded push).
- `workspace_sync_service.dart` — the Hive → disk mirror itself.

**Blocs (`lib/features/collections/presentation/bloc/`):** `git_sync_bloc.dart`, `review_bloc.dart`, `pull_requests_bloc.dart`, `conflict_bloc.dart`. All are droppable-while-busy so a second op can't race git over a tree the first is mid-change.

**UI (`lib/features/collections/presentation/widgets/`):** `branch_chip.dart` (the entry point in the collections list — branch/sync status + menu), `review_changes_button.dart` + `review_changes_dialog.dart`, `pull_requests_dialog.dart`, `conflict_resolution_dialog.dart`, `workspace_settings_tile.dart` (Settings → Workspace: pick/clear the workspace folder + git identity), and the widget-layer coordinators `workspace_sync_listener.dart` (mirrors CollectionsBloc changes to disk) + `branch_sync_listener.dart` (reloads the tree after a branch switch/pull).

**Pure merge logic (`lib/features/collections/domain/logic/`):** `semantic_diff.dart`, `three_way_merge.dart`.

**DI:** `injection_container.dart` registers `GitService`/`GhService` (io/stub factories) and the four services as lazy singletons over them, plus the four blocs as factories.

## Key mechanisms

### Commit identity (never touches the user's git config)

Commit-creating ops (`commit`, `pull`'s autostash replay, `rebaseContinue`) take optional `authorName`/`authorEmail` from Settings (`HiveField(28/29)`), applied inline as `-c user.name=… -c user.email=…` — **never written to the global git config**. The stored name is suffixed " via Getman" at commit time only (GitHub still credits the user by email). When no identity is set and git can't resolve one, the raw failure is detected via `GitException.isMissingIdentity` and the blocs surface a friendly "Set your commit identity in Settings → Workspace, then try again" — not git's `git config --global …` advice, which contradicts the no-config-file approach.

### Mirror-race discipline

Every op that reads or mutates the working tree first flushes the pending Hive → disk mirror (`_flushOrThrow`) and **aborts if the write failed** (a stale tree must never be handed to git). Ops that also *rewrite* the tree (switch/pull/stash/pop, and the conflict resolve/continue) additionally suspend mirroring for their duration and the reload that follows (`_runOnTree` / `WorkspaceSyncService.withMirroringSuspended`), so an edit made mid-checkout can't fire its debounce afterward and write the old branch's tree onto the new branch. Ops that don't touch the tree (create/push/addRemote/dropStash/fetch) deliberately skip suspension.

### Pull outcomes

`pull` is `git pull --rebase --autostash` (the tree is routinely dirty because in-app edits mirror to disk). A true rebase conflict is left **paused** (`PullOutcome.conflicted`) for the resolver. A conflicted *autostash re-apply* restores the clean rebased tree and keeps the edits safely in `stash@{0}` (`PullOutcome.cleanEditsStashed`). Any other failure (auth/network) aborts the rebase before throwing. `GitSyncBloc._onPull` bumps `reloadToken` on a clean pull and `conflictToken` (never reload) on a conflicted one.

### Semantic conflict resolution

`GitConflictService` classifies each conflicted path over the paused rebase: `.req.json` and `.folder.json` files are parsed at merge stages 1/2/3 (base/incoming/yours) and field-level 3-way merged via `ThreeWayMerge`. Delete/modify (one side's stage absent), add/add (no base), and unparseable stages (→ structural) are distinguished. The user's picks are applied on top of the merged skeleton, serialized, written to the working tree, and staged; then `rebase --continue` (identity threaded) advances to the next batch or finishes.

### Reload after a tree-changing op

`BranchSyncListener` watches `GitSyncBloc` and, on a reload/conflict token bump, re-reads the forest from disk and dispatches `ReplaceCollections` — with mirroring suspended (to avoid a reload → mirror → reload loop) — carrying along any open tabs whose linked request is untouched so they show the new version.

## Flows

1. **Review & commit:** BranchChip / review button → `ReviewChangesDialog` (`ReviewBloc` → `ReviewService.review`, which flushes the mirror then diffs `git status` semantically) → stage/unstage (a select-all is one git call) → commit (identity threaded). git's index is the source of truth, so each mutation re-runs the review.
2. **Branch & sync:** BranchChip → `GitSyncBloc` over `BranchService` — status / switchTo / create / pull / push / stash / popStash / dropStash / addRemote / fetch.
3. **Pull request:** `PullRequestsDialog` (`PullRequestsBloc` → `PullRequestService`) — availability (gh installed + authenticated), list open PRs (with a rolled-up check verdict), and create (pushes the branch first via the flush-guarded push, then `gh pr create`). `defaultBase` is cached per workspace root.
4. **Conflict resolution:** `ConflictResolutionDialog` (`ConflictBloc` → `ConflictService`) — `LoadConflicts` (classify + pre-merge) → `ResolveAndContinue` (apply picks, stage, `rebase --continue`) one batch at a time → `AbortRebase`. The rebase is never auto-aborted on error — it's left paused so no work is lost.

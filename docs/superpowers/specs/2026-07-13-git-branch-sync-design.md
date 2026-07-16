# Spec B — Branch & sync (git-native collaboration, 2 of 4)

Date: 2026-07-13
Status: approved, ready to plan
Depends on: [Spec A — Review & commit](2026-06-26-git-native-collaboration-design.md)
(shipped in PR #50: `GitService`, semantic diff, `WorkspaceReviewService`,
`ReviewBloc`, Review Changes dialog)

## Summary

Make the git workspace **collaborative**. Spec A can commit but never share.
Spec B adds the operations that move commits between machines: list/switch/
create branches, pull, push, and stash — driven from a **branch chip** in the
collections header, with the collections tree reloaded from disk whenever git
changes the files underneath the app.

Desktop only (web-gated, like Spec A). Getman drives the system `git` CLI and
**stores no credentials**.

## Why this shape

Getman already mirrors collections to a diff-friendly on-disk tree and can
reload disk → Hive. Spec A turned that tree into a git repo Getman drives. The
only thing standing between that and real team collaboration is the network
half of git — which is exactly what this spec adds, and nothing more.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Credentials | **None stored.** Shell out to `git`; the user's SSH agent / credential helper authenticates, as it does in their terminal. | Zero secret-handling surface. Hive is unencrypted; a stored PAT would need masking, log-scrubbing, and a threat model we don't want. Auth errors surface git's own message. |
| Dirty branch switch | **Blocked**, with a prompt offering *Review changes…* (commit) or *Stash changes*. | Matches git's own refusal to clobber. Never loses work, and the user already has a commit UI. |
| Pull strategy | **`--rebase`; on conflict `rebase --abort`** and surface the error. | Keeps collection history linear and readable. Aborting returns the workspace byte-identical to its prior state rather than stranding the user mid-rebase with no conflict UI (that is Spec D). |
| Push | Sets upstream on first push (`-u origin <branch>`). Disabled when the repo has no remote. | The common case is a branch created in-app that has never been pushed. |
| UI | **Branch chip in the collections header** (`master ↑2 ↓3`) opening a menu. | Ahead/behind is visible at a glance without opening a dialog — the same instinct as the Review badge. |
| Stash | Included, **with a stash list** (view / pop / drop). | A stash Getman creates but cannot show again is invisible work. If we offer stashing, we owe the user a way back to it. |

## Architecture

Three layers, mirroring Spec A.

### 1. `GitService` — extend (`lib/core/git/`, web-gated)

Still the sole `dart:io` importer; still `Process.run('git', [args])` with no
shell (so no injection). New methods:

```dart
Future<List<String>> branches(String root);              // local branches
Future<void> createBranch(String root, String name);     // switch -c
Future<void> switchBranch(String root, String name);     // switch
Future<bool> hasRemote(String root);                     // remote -v non-empty
Future<AheadBehind> aheadBehind(String root);            // rev-list --left-right --count @{u}...HEAD
Future<void> pull(String root);                          // pull --rebase (abort on conflict)
Future<void> push(String root, {required bool setUpstream});
Future<List<StashEntry>> stashList(String root);         // stash list --porcelain-ish
Future<void> stashPush(String root, String message);     // stash push -u
Future<void> stashPop(String root, int index);
Future<void> stashDrop(String root, int index);
```

`pull` is the only method with recovery logic: if the rebase reports a
conflict, it runs `git rebase --abort` **before** throwing, so a failed pull is
a no-op on the working tree.

`aheadBehind` returns `(0, 0)` when there is no upstream rather than throwing —
a brand-new local branch is a normal state, not an error.

### 2. Domain `BranchService` (abstract) — `collections/domain/`

The bloc depends on this, never on the concrete implementation (enforced by the
`bloc_depends_on_abstractions` custom_lint rule; this is why Spec A introduced
`ReviewService`).

```dart
class BranchStatus {           // Equatable
  final String? current;       // null when not a repo
  final List<String> branches;
  final int ahead;
  final int behind;
  final bool hasRemote;
  final int stashCount;
}

abstract class BranchService {
  Future<BranchStatus> status(String root);
  Future<bool> isDirty(String root);
  Future<void> switchTo(String root, String branch);
  Future<void> create(String root, String branch);
  Future<void> pull(String root);
  Future<void> push(String root);
  Future<List<StashEntry>> stashes(String root);
  Future<void> stash(String root, String message);
  Future<void> popStash(String root, int index);
  Future<void> dropStash(String root, int index);
}
```

Implemented in `data/services/` by `GitBranchService` over `GitService`.
`push` resolves `setUpstream` itself from the current ahead/behind state, so the
bloc never encodes git mechanics.

### 3. `GitSyncBloc` — `collections/presentation/bloc/`

Holds `BranchStatus` + a status enum (`idle`/`busy`/`error`) + `errorMessage`.
Events: `LoadBranchStatus`, `SwitchBranch`, `CreateBranch`, `Pull`, `Push`,
`StashChanges`, `PopStash`, `DropStash`.

Errors are **surfaced, not logged away** — the same lesson as Spec A's final
review, where a failed commit was silently swallowed. Every failed action sets
`errorMessage`, which the chip menu renders in a banner.

After a successful `SwitchBranch` or `Pull`, the bloc bumps a
`reloadToken` (an int) in its state. That token is the reload signal — see
below.

## The two hazards

### Hazard 1 — the pending-mirror race (must-fix)

`WorkspaceSyncService.scheduleMirror` is **debounced by 1 second**. If the user
edits a request and switches branch within that window:

1. the mirror write has not landed, so `git status` reports the workspace clean;
2. the dirty check passes and we check out the target branch;
3. the timer then fires and writes the edited request **onto the new branch**.

Fix: `WorkspaceSyncService` gains `Future<void> flushPending()` — cancel the
timer and run the pending write to completion (a no-op if none is pending).
`GitBranchService` calls it **before** `isDirty` on every mutating operation
(switch, create, pull, push, stash). This is a required regression test.

### Hazard 2 — reloading without bloc-to-bloc coupling

A checkout or pull changes the files under the app, but Hive is the in-session
source of truth, so the tree must be reloaded disk → Hive. `GitSyncBloc` must
not know about `CollectionsBloc` (the project bans bloc→bloc coupling; the
coordinator is always the widget holding both).

So the reload is a **widget-layer coordinator**, `BranchSyncListener`, in the
same family as the existing `WorkspaceSyncListener` and
`ChainingWriteBackListener`: it listens to `GitSyncBloc` for a changed
`reloadToken`, reads the workspace via `WorkspaceSyncService.read(root)`, and
dispatches `ReplaceCollections(...)` on `CollectionsBloc`.

Note the benign echo: `ReplaceCollections` triggers `WorkspaceSyncListener`,
which mirrors the tree back to disk — writing exactly the bytes we just read.
Harmless, and not worth suppressing.

## UI

**Branch chip** in the collections header, left of the Review Changes button
(`collections_list.dart`), hidden on web and when no workspace is connected —
consistent with the Review button, which routes to the WORKSPACE settings pane
when unconfigured.

```
┌───────────────────────────────┐
│ ⚇ master ↑2 ↓3 │ ⇧ │ ≣✗ ②     │
└───────────────────────────────┘
  click → menu:
    ✓ master
      feat/new-auth
    ───────────────
    + New branch…
    ↓ Pull (rebase)
    ↑ Push
    ⚇ Stashes (1)
```

- Ahead/behind arrows are hidden when zero; the whole chip is hidden when the
  workspace is not a git repo (the Review dialog already handles `git init`).
- **Pull/Push** show a busy state while running and are disabled with
  "No remote configured" when `hasRemote` is false.
- **Switching while dirty** opens a prompt: *"You have uncommitted changes"* →
  **REVIEW CHANGES…** (opens the Spec A dialog) or **STASH CHANGES**.
- **New branch…** uses the existing `NamePromptDialog`.
- **Stashes** opens a small list dialog: message + POP + DROP per row
  (`ConfirmDialog` on drop, per the irreversible-action convention).
- All strings/sizes/colors come from the theme extensions. No `Colors.*`
  literals, no `GetIt` in widgets.

## Testing

- **`GitService` (io)** — integration tests against a **real temp repo**, with a
  local **bare repo as the remote** so push/pull need no network: branches,
  create, switch, ahead/behind, push (incl. first-push upstream), pull
  fast-forward, **pull conflict → aborted and tree unchanged**, stash
  push/list/pop/drop. Skipped when `git` is absent.
  Spec A's `-uall` bug is the lesson here: mocked git output hides real git
  behavior, so these must run against actual git.
- **`WorkspaceSyncService.flushPending`** — the debounce race: schedule a
  mirror, flush, assert the write landed before the next read.
- **`GitBranchService`** — unit tests with a fake `GitService`: dirty blocks a
  switch; flush happens before the dirty check; push sets upstream only when
  there is no upstream.
- **`GitSyncBloc`** — `bloc_test`: load, switch (clean/dirty), pull error →
  `errorMessage`, push, stash; `reloadToken` bumps only on success.
- **`BranchSyncListener`** — widget test: a bumped token triggers exactly one
  `ReplaceCollections`.
- **Chip + menu + dirty prompt + stash dialog** — widget tests, incl. an
  overflow guard.

Full existing gate applies: `flutter analyze`, `custom_lint`, the lints
fixtures self-test, `bloc_lint`, `dart format`, and a green `flutter test`.

## Boundaries

- **No conflict resolution UI.** A conflicting pull aborts and tells the user to
  resolve it in their git tool. That is Spec D.
- **No PR creation / GitHub API.** That is Spec C.
- **No credential storage**, no modification of the user's git config or
  identity.
- **No fetch-on-a-timer / file watcher.** Ahead/behind refreshes when the
  workspace mirror lands, on branch actions, and on app start — not on a poll.
  (Ahead/behind is computed against the last fetched remote state; a `Pull`
  refreshes it.)
- **Collections only.** Environments remain unversioned.
- Remote-tracking state comes from whatever the user's git already fetched;
  Getman does not fetch in the background.

## Docs

The **Version Control** wiki page (already owed from Spec A, deferred to its
merge) gains a Branch & sync section: the chip, switching, pull/push,
credentials ("Getman uses your existing git credentials — nothing is stored"),
and the conflict boundary.

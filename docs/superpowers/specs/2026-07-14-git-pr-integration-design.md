# Spec C — Pull Request Integration (design)

**Status:** approved 2026-07-14. Branch `feat/git-pr-integration` (off Spec B's
`feat/git-branch-sync`). Third spec in the git-native-collaboration roadmap
(A = review & commit / PR #50; B = branch & sync / PR #51).

## Goal

Create GitHub pull requests and see the repo's open PRs (state + checks) from
inside Getman, layered on the git-friendly collections workspace — without the
app ever storing a credential.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Scope (v1) | Create PRs **and** list open PRs with state + checks | The useful slice; reviewing/merging in-app is out of scope. |
| Transport / auth | Shell out to the **`gh` CLI** | Rides on the user's existing `gh auth` exactly as we ride on git's credentials — **nothing stored**. Same shell-out + web-stub architecture as `GitService`. `gh --json` is machine-readable and handles enterprise/other hosts transparently. |
| Unpushed branch | **Push (`-u`), then create** | One action opens a PR even on a never-pushed branch; reuses Spec B's flush-guarded push. |
| `gh` missing | **Prompt to install** it (link to `cli.github.com`) | Explicit, actionable; no silent failure. |
| `gh` present but unauthenticated | **Prompt to run `gh auth login`** | Distinct state from "not installed". |
| Entry point | **PULL REQUESTS…** item in the branch-chip menu → `PullRequestsDialog` | No new header control (the header was just decluttered). |
| List scope | **Open PRs only** | Focused v1; merged/closed can be a later toggle. |
| Draft | **"Create as draft" toggle** in the create form (`gh pr create --draft`) | One flag, genuinely useful. |
| Credentials | **None stored**, git config never edited | Same guarantee as Spec B; `gh` owns auth. |
| Platform | **Desktop only** (web-stubbed + `kIsWeb`) | `gh` is a desktop binary. |

## Architecture (three layers, mirroring Spec A/B)

### Core — `lib/core/git/`
`GhService` (abstract) + `gh_service_io.dart` (the only `dart:io` importer;
shells out to `gh` via `Process.run`, no shell so no injection) +
`gh_service_stub.dart` (web no-op). Surface:

- `Future<bool> isAvailable()` — `gh --version` exit 0.
- `Future<bool> isAuthenticated(String root)` — `gh auth status` exit 0.
- `Future<PullRequestRef> createPr(String root, {required String base, required String title, required String body, required bool draft})` — `gh pr create --base <base> --title <title> --body <body> [--draft]`; parses the returned PR URL/number.
- `Future<List<PullRequestInfo>> listPrs(String root)` — `gh pr list --state open --json number,title,state,url,isDraft,statusCheckRollup` (one call yields state **and** checks). `statusCheckRollup` is rolled into a simple `PrChecks` verdict: `none` (no checks) / `pending` / `passing` / `failing`.
- `Future<String?> defaultBranch(String root)` — `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, for the create form's base default. Falls back to `null` (form then defaults base to the current branch's list).

`PullRequestRef {number, url}` and `PullRequestInfo {number, title, state, url,
isDraft, checks}` are plain core types (like `AheadBehind` / `StashEntry`).

### Domain — `lib/features/collections/domain/`
- `entities/pull_request.dart` — `PullRequestEntity {int number, String title, PrState state, String url, bool isDraft, PrChecks checks}` (Equatable); enums `PrState {open, merged, closed}` and `PrChecks {none, pending, passing, failing}`.
- `pull_request_service.dart` — abstract `PullRequestService`: `availability()` → `GhAvailability {available, notInstalled, notAuthenticated}`, `list(root)`, `create(root, {...})`, `defaultBase(root)`.

### Data — `lib/features/collections/data/services/`
`GhPullRequestService implements PullRequestService`, composing `GhService` +
the existing `BranchService`. `create(...)` does: if the branch has no upstream
(`BranchService`/`GitService` already exposes this), call `BranchService`'s
flush-guarded push with `setUpstream: true`, **then** `GhService.createPr`. This
reuses Spec B's mirror-flush guarantee rather than duplicating it — no new race
surface, because PR creation itself never touches the working tree.

### Presentation — `lib/features/collections/presentation/`
- `bloc/pull_requests_bloc.dart` (+ event/state) — depends **only** on the
  `PullRequestService` abstraction (`bloc_depends_on_abstractions`). Events:
  `LoadPullRequests(root)`, `CreatePullRequest(root, base, title, body, draft)`.
  State: `{PrLoadStatus status, GhAvailability availability, List<PullRequestEntity> prs, String? errorMessage, PullRequestRef? lastCreated}`. Droppable while busy (like `GitSyncBloc`).
- `widgets/pull_requests_dialog.dart` — reached via the branch-chip menu. Renders
  one of: install prompt / auth prompt / the list + REFRESH + CREATE PULL
  REQUEST…. The create form (base picker, title, body, draft toggle) is a nested
  view or second dialog. A row opens its PR URL in the browser.

## Flows

**Open the dialog:** branch chip → PULL REQUESTS… → `LoadPullRequests` →
`availability()` decides which of the three views renders; if ready, `list()`
populates.

**Create:** fill the form → `CreatePullRequest` → (push if no upstream) →
`gh pr create` → on success, surface the PR number with an "open in browser"
action and refresh the list. Any `gh` failure lands in `errorMessage` and a GIT
ERROR-style dialog (consistent with the branch chip).

**After a create that pushed:** the branch's ahead/behind changed, so the branch
chip should refresh. The dialog and `GitSyncBloc` are both in scope under the
collections header, so a widget-layer nudge (dispatch `LoadBranchStatus` on
`GitSyncBloc`) refreshes the chip — no bloc→bloc coupling.

## Error handling

- `gh` non-zero exit → `GhException` (mirrors `GitException`), message surfaced.
- Availability is checked before every dialog open, not cached, so installing /
  authenticating `gh` and reopening the dialog just works.
- Best-effort browser open: a failure to launch the browser shows a snackbar,
  never throws.

## Testing

- `GhService` `_io`: parse `createPr` output and `listPrs --json` against
  captured fixture strings (incl. the `statusCheckRollup` → `PrChecks` mapping
  for none/pending/passing/failing, and a draft PR). `isAvailable` /
  `isAuthenticated` gated on real `gh` presence (skip when absent), like the
  `GitService` tests skip when `git` is absent.
- `GhPullRequestService`: push-then-create ordering — a mock `BranchService`
  push must run **before** `GhService.createPr`, and only when there is no
  upstream (verify non-vacuously with a Completer gate, per the Spec B lesson
  that a `thenAnswer((_) async {})` stub satisfies `verifyInOrder` vacuously).
- `PullRequestsBloc`: each availability branch; load populates; create dispatches
  through the service and refreshes; error surfaces; droppable-while-busy.
- `PullRequestsDialog`: the three views render; a row opens the URL; CREATE opens
  the form; blocs built **inside** the test body with a theme provided.
- Full done-bar (analyze, custom_lint, bloc_lint, fixtures self-test, format,
  100% tests).

## Out of scope (v1)

Reviewing/approving/merging PRs in-app; comment threads; non-GitHub hosts beyond
whatever `gh` already supports; listing merged/closed PRs; CI log viewing.

## Hazards / notes

- **Non-interactive shell-out:** `gh` must never be run in a mode that prompts on
  stdin (e.g. `gh pr create` on a branch with no upstream prompts interactively).
  We push first precisely to avoid that; all `gh` calls run with stdin closed and
  are treated as failed if they would block.
- **Wiki:** the Version Control page (Spec B) gains a "Pull requests" section —
  part of this spec's final task, per the keep-the-wiki-in-sync mandate.

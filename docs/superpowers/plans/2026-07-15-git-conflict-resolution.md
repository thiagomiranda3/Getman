# Git Semantic Conflict Resolution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve `git pull --rebase` conflicts inside Getman field-by-field (3-way auto-merge, prompt only on true overlaps), plus auto-fetch + a manual FETCH action.

**Architecture:** Same three layers as Specs A/B/C. Core `GitService` gains conflict + fetch primitives (sole `dart:io` boundary, web-stubbed). A pure `ThreeWayMerge` engine + `ConflictService` abstraction in domain. `GitConflictService` (data) composes `GitService` + the existing `WorkspaceCollectionSerializer`. `ConflictBloc` + `ConflictResolutionDialog` in presentation, driven from the pull flow. Fetch rides on `GitSyncBloc` + a `BranchChip` timer.

**Tech Stack:** Flutter, flutter_bloc, get_it, equatable, mocktail, bloc_test. `fvm flutter ...` / `fvm dart ...` always.

## Global Constraints

- **fvm always:** `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib < /dev/null`, `( cd tools/getman_lints/example && fvm dart run custom_lint )`, `fvm dart format lib test tools`, `fvm flutter test` — all clean before a task is done.
- **Commits** authored `thiago.cortez81@gmail.com` + `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. No Claude Code mention in PR bodies.
- **No credentials stored; git config never edited.** All `dart:io` + git in `*_io.dart`; web stubs. Desktop-only (`kIsWeb` gates).
- **Domain has zero infrastructure imports** (`domain_no_infrastructure_imports`); **blocs depend only on abstractions** (`bloc_depends_on_abstractions`); **no `sl<T>()` in widgets**; **no bloc→bloc coupling** (cross-bloc coordination in a widget); **Equatable props complete**.
- **Non-interactive git:** `Process.run` with stdin closed; `rebase --continue` runs with `GIT_EDITOR=true` so it never opens an editor.
- **Rebase ours/theirs are swapped vs a merge:** stage `:2` = **Incoming** (upstream), `:3` = **Yours** (your replayed commit). The engine and UI must respect this.

---

## File Structure

- `lib/core/git/git_service.dart` — extend abstract surface + `PullOutcome`.
- `lib/core/git/git_service_io.dart` — implement primitives (dart:io).
- `lib/core/git/git_service_stub.dart` — web no-ops.
- `lib/features/collections/domain/logic/three_way_merge.dart` — pure merge engine (NEW).
- `lib/features/collections/domain/entities/file_conflict.dart` — conflict entities (NEW).
- `lib/features/collections/domain/conflict_service.dart` — abstraction (NEW).
- `lib/features/collections/data/services/git_conflict_service.dart` — impl (NEW).
- `lib/features/collections/domain/branch_service.dart` + `data/services/git_branch_service.dart` — add `fetch`.
- `lib/features/collections/presentation/bloc/conflict_bloc.dart` / `_event.dart` / `_state.dart` (NEW).
- `lib/features/collections/presentation/bloc/git_sync_event.dart` — add `FetchRemote`.
- `lib/features/collections/presentation/bloc/git_sync_bloc.dart` — handle `FetchRemote`; pull returns outcome.
- `lib/features/collections/presentation/widgets/conflict_resolution_dialog.dart` (NEW).
- `lib/features/collections/presentation/widgets/branch_chip.dart` — FETCH menu item + auto-fetch timer + open resolver on conflicted pull.
- `lib/core/di/injection_container.dart` + `lib/main.dart` — register `ConflictService` + `ConflictBloc`.

---

## Task 1: GitService — conflict + fetch primitives, `PullOutcome`

**Files:**
- Modify: `lib/core/git/git_service.dart`, `git_service_io.dart`, `git_service_stub.dart`
- Test: `test/core/git/git_conflict_primitives_io_test.dart`

**Interfaces produced (add to abstract `GitService`):**
```dart
/// The result of a rebase-pull: it either fast-forwarded/rebased cleanly, or it
/// stopped on conflicts that are now sitting in the index for resolution.
enum PullOutcome { clean, conflicted }

Future<PullOutcome> pull(String root); // CHANGED from Future<void>
Future<bool> isRebaseInProgress(String root);
Future<List<String>> conflictedPaths(String root);
/// Content of [path] at merge stage [stage] (1=base, 2=ours/incoming, 3=theirs/yours),
/// or null when that stage is absent (e.g. add/add has no base).
Future<String?> showStage(String root, String path, int stage);
Future<void> writeWorkingFile(String root, String path, String content);
Future<void> add(String root, String path);
Future<void> rebaseContinue(String root);
Future<void> rebaseAbort(String root);
Future<void> fetch(String root);
```

- [ ] **Step 1: Write the failing io test** — `test/core/git/git_conflict_primitives_io_test.dart`, `@TestOn('vm')`. Skip when git is absent (mirror `gh_service_io_test.dart`). Script a real conflicting rebase in a temp repo and assert the primitives:
```dart
@TestOn('vm')
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';

void main() {
  late GitService git;
  late Directory tmp;

  Future<bool> gitPresent() async => git.isAvailable();
  Future<void> run(String dir, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir);
    if (r.exitCode != 0) throw Exception('git ${args.join(' ')}: ${r.stderr}');
  }

  setUp(() async {
    git = createGitService();
    tmp = await Directory.systemTemp.createTemp('getman_conflict');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('a conflicting rebase exposes stages, resolves, and continues', () async {
    if (!await gitPresent()) return; // skip when git is absent
    final root = tmp.path;
    await run(root, ['init', '-b', 'main']);
    await run(root, ['config', 'user.email', 't@t.co']);
    await run(root, ['config', 'user.name', 't']);
    final f = File('$root/a.req.json')..writeAsStringSync('{"v":0}\n');
    await run(root, ['add', '.']);
    await run(root, ['commit', '-m', 'base']);
    // upstream commit
    f.writeAsStringSync('{"v":1}\n');
    await run(root, ['commit', '-am', 'upstream']);
    await run(root, ['branch', 'feature', 'HEAD~1']);
    await run(root, ['switch', 'feature']);
    f.writeAsStringSync('{"v":2}\n');
    await run(root, ['commit', '-am', 'yours']);
    // rebase feature onto main → conflict
    final r = await Process.run('git', ['rebase', 'main'], workingDirectory: root);
    expect(r.exitCode, isNot(0));

    expect(await git.isRebaseInProgress(root), isTrue);
    expect(await git.conflictedPaths(root), contains('a.req.json'));
    expect(await git.showStage(root, 'a.req.json', 1), contains('"v":0'));
    expect(await git.showStage(root, 'a.req.json', 2), contains('"v":1')); // incoming (main)
    expect(await git.showStage(root, 'a.req.json', 3), contains('"v":2')); // yours

    await git.writeWorkingFile(root, 'a.req.json', '{"v":9}\n');
    await git.add(root, 'a.req.json');
    await git.rebaseContinue(root);
    expect(await git.isRebaseInProgress(root), isFalse);
    expect(File('$root/a.req.json').readAsStringSync(), contains('"v":9'));
  });

  test('rebaseAbort restores the pre-rebase tree', () async {
    if (!await gitPresent()) return;
    // ... (same setup to the conflicted state) ...
    // await git.rebaseAbort(root); expect isRebaseInProgress false.
  });
}
```
- [ ] **Step 2: Run, verify fail** — `fvm flutter test test/core/git/git_conflict_primitives_io_test.dart` → FAIL (methods undefined). (If git is absent the tests early-return; implement anyway.)
- [ ] **Step 3: Implement in `git_service_io.dart`.** Add a stdin-closed, editor-disabled runner for rebase-continue:
```dart
@override
Future<PullOutcome> pull(String root) async {
  final r = await _run(root, ['pull', '--rebase'], allowFailure: true);
  if (r.exitCode == 0) return PullOutcome.clean;
  if (await isRebaseInProgress(root) && (await conflictedPaths(root)).isNotEmpty) {
    return PullOutcome.conflicted; // leave paused for the resolver
  }
  // Not a resolvable conflict (auth/network/local changes) — restore + throw.
  await _run(root, ['rebase', '--abort'], allowFailure: true);
  final err = (r.stderr as String).trim();
  throw GitException(err.isEmpty ? 'git pull failed' : err, exitCode: r.exitCode);
}

@override
Future<bool> isRebaseInProgress(String root) async {
  final r = await _run(root, ['rev-parse', '--git-path', 'rebase-merge'],
      allowFailure: true);
  final merge = (r.stdout as String).trim();
  if (merge.isNotEmpty && Directory('$root/$merge').existsSync()) return true;
  final r2 = await _run(root, ['rev-parse', '--git-path', 'rebase-apply'],
      allowFailure: true);
  final apply = (r2.stdout as String).trim();
  return apply.isNotEmpty && Directory('$root/$apply').existsSync();
}

@override
Future<List<String>> conflictedPaths(String root) async {
  final r = await _run(root, ['diff', '--name-only', '--diff-filter=U']);
  return (r.stdout as String).split('\n').map((l) => l.trim())
      .where((l) => l.isNotEmpty).toList();
}

@override
Future<String?> showStage(String root, String path, int stage) async {
  final r = await _run(root, ['show', ':$stage:$path'], allowFailure: true);
  return r.exitCode == 0 ? r.stdout as String : null;
}

@override
Future<void> writeWorkingFile(String root, String path, String content) async {
  final file = File('$root/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

@override
Future<void> add(String root, String path) => _run(root, ['add', path]);

@override
Future<void> rebaseContinue(String root) async {
  // GIT_EDITOR=true so a commit-message step never blocks on an editor.
  final r = await Process.run('git', ['rebase', '--continue'],
      workingDirectory: root, stdoutEncoding: utf8, stderrEncoding: utf8,
      environment: {'GIT_EDITOR': 'true'});
  if (r.exitCode != 0) {
    throw GitException((r.stderr as String).trim().isEmpty
        ? 'git rebase --continue failed' : (r.stderr as String).trim(),
        exitCode: r.exitCode);
  }
}

@override
Future<void> rebaseAbort(String root) => _run(root, ['rebase', '--abort']);

@override
Future<void> fetch(String root) => _run(root, ['fetch']);
```
- [ ] **Step 4: Stub in `git_service_stub.dart`** — `pull` → `PullOutcome.clean`; `isRebaseInProgress` → false; `conflictedPaths` → `const []`; `showStage` → null; `writeWorkingFile`/`add`/`rebaseContinue`/`rebaseAbort`/`fetch` → no-op `async {}`.
- [ ] **Step 5: Run, verify green** — the io test passes (or skips when git absent). Also update any existing caller of `pull` for the new return type (Task 4 fixes `GitBranchService`).
- [ ] **Step 6: Gate + commit** — analyze/custom_lint/format/test; `feat(git): GitService conflict + fetch primitives`.

---

## Task 2: `ThreeWayMerge` — the pure field-level merge engine

**Files:**
- Create: `lib/features/collections/domain/logic/three_way_merge.dart`
- Test: `test/features/collections/domain/logic/three_way_merge_test.dart`

**Interfaces produced:**
```dart
enum FieldConflictKind { scalar, mapEntry, opaque, list }

class FieldConflict extends Equatable {           // one unresolved field
  const FieldConflict({required this.field, required this.kind,
    this.incoming, this.yours});
  final String field;          // e.g. "url", "header 'X-Token'", "authentication"
  final FieldConflictKind kind;
  final String? incoming;      // null = opaque (auth/form) — no value shown
  final String? yours;
}

class NodeMergeResult {
  const NodeMergeResult({required this.merged, required this.conflicts});
  final CollectionNodeEntity merged;    // auto-merged fields applied; conflicts left = incoming
  final List<FieldConflict> conflicts;  // empty => fully auto-resolved
}

class ThreeWayMerge {
  const ThreeWayMerge._();
  /// [base]/[incoming]/[yours] are request leaves (isFolder=false). Any may be null.
  static NodeMergeResult mergeRequest(CollectionNodeEntity? base,
      CollectionNodeEntity? incoming, CollectionNodeEntity? yours);
  /// Folder nodes; [childOrderX] are the persisted childOrder lists.
  static NodeMergeResult mergeFolder(
      CollectionNodeEntity? base, List<String> baseOrder,
      CollectionNodeEntity? incoming, List<String> incomingOrder,
      CollectionNodeEntity? yours, List<String> yoursOrder);
}
```

**Per-field rule (private helpers):**
- `_pick3(b, i, y)`: if `i == y` → value `i`, no conflict. If `i == b` → auto-merge `y`. If `y == b` → auto-merge `i`. Else → **conflict** (candidates `i`/`y`).
- Scalars: `method, url, bodyType.wire, body, graphqlVariables, bodyFilePath` (config); `name, isFavorite` (leaf). Build the merged config from the auto-merged sides; unresolved scalars are left at `incoming` in `merged` and reported as `FieldConflict(kind: scalar)`.
- Maps (`headers`, folder `variables`): per key over `{...base, ...incoming, ...yours}.keys` → `_pick3(base[k], incoming[k], yours[k])`; a conflicting key → `FieldConflict(field: "header '$k'", kind: mapEntry)`.
- `auth`: opaque — if `!mapEq(incoming.auth, yours.auth)` and both differ from base → `FieldConflict(field: 'authentication', kind: opaque, incoming: null, yours: null)`; else auto-merge the side that changed.
- `formFields`: list — same opaque/whole-field rule (`kind: list`, values null).
- Folder `childOrder`: treat as a scalar over the joined string (`FieldConflict(field: 'child order', kind: scalar, incoming: order.join(', '), yours: ...)`).

- [ ] **Step 1: Write the failing tests.** Cover:
  - non-overlapping scalars auto-merge (incoming changed url, yours changed method → 0 conflicts, merged has both).
  - true scalar overlap (both changed url differently → 1 conflict).
  - map: different keys auto-merge; same key/diff value conflicts.
  - auth opaque conflict has null values.
  - add/add (base null) both-parseable → conflicts on differing fields, no crash.
  - zero-true-conflict file → `conflicts.isEmpty` and `merged` carries both sides' changes.
```dart
test('non-overlapping scalar edits auto-merge with no conflict', () {
  final base = _leaf(url: 'a', method: 'GET');
  final incoming = _leaf(url: 'b', method: 'GET');   // changed url
  final yours = _leaf(url: 'a', method: 'POST');     // changed method
  final r = ThreeWayMerge.mergeRequest(base, incoming, yours);
  expect(r.conflicts, isEmpty);
  expect(r.merged.config!.url, 'b');
  expect(r.merged.config!.method, 'POST');
});
test('a true url overlap is one conflict', () {
  final r = ThreeWayMerge.mergeRequest(
    _leaf(url: 'a'), _leaf(url: 'b'), _leaf(url: 'c'));
  expect(r.conflicts.map((c) => c.field), ['url']);
  expect(r.conflicts.single.incoming, 'b');
  expect(r.conflicts.single.yours, 'c');
});
// ...map per-key, auth opaque, add/add, folder childOrder...
```
- [ ] **Step 2: Run, verify fail.** `fvm flutter test .../three_way_merge_test.dart` → FAIL (undefined).
- [ ] **Step 3: Implement `three_way_merge.dart`** per the rules above. Pure Dart + equatable + collection (`MapEquality`/`ListEquality`) only — no Flutter/dio/hive imports (domain rule).
- [ ] **Step 4: Run, verify green.**
- [ ] **Step 5: Gate + commit** — `feat(collections): ThreeWayMerge field-level merge engine`.

---

## Task 3: Domain — `FileConflict` entities + `ConflictService` abstraction

**Files:**
- Create: `lib/features/collections/domain/entities/file_conflict.dart`, `lib/features/collections/domain/conflict_service.dart`
- Test: `test/features/collections/domain/entities/file_conflict_test.dart`

**Interfaces produced:**
```dart
// file_conflict.dart
enum ConflictKind { request, folder, addAdd, deleteModify, structural }

class FileConflict extends Equatable {
  const FileConflict({required this.path, required this.kind, this.node});
  final String path;
  final ConflictKind kind;
  final NodeMergeResult? node;   // present for request/folder (field-level); null for coarse
  bool get isFieldLevel => node != null;
  @override List<Object?> get props => [path, kind]; // node compared by identity is fine
}

/// One user decision. For field-level: a map of field-label → chosen value
/// (an edited string, or the picked incoming/yours). For coarse: a whole-file side.
enum FileSide { incoming, yours }
class FileResolution extends Equatable {
  const FileResolution({required this.path, this.fieldChoices = const {},
    this.wholeFile});
  final String path;
  final Map<String, String> fieldChoices;   // field-label → resolved string value
  final FileSide? wholeFile;                 // set for coarse/structural files
  @override List<Object?> get props => [path, fieldChoices, wholeFile];
}

enum RebaseStep { done, moreConflicts }

// conflict_service.dart
abstract class ConflictService {
  Future<PullOutcome> pullOrConflict(String root);   // rides GitService.pull
  Future<List<FileConflict>> currentConflicts(String root);
  Future<void> resolve(String root, List<FileResolution> resolutions);
  Future<RebaseStep> continueRebase(String root);
  Future<void> abort(String root);
  Future<void> fetch(String root);
}
```
- [ ] **Step 1: Write the failing test** — equality of `FileConflict`/`FileResolution` by value.
- [ ] **Step 2/3/4:** run-fail → implement → run-green.
- [ ] **Step 5: Gate + commit** — `feat(collections): FileConflict entities + ConflictService`.

---

## Task 4: Data — `GitConflictService` + `BranchService.fetch` + DI

**Files:**
- Create: `lib/features/collections/data/services/git_conflict_service.dart`
- Modify: `lib/features/collections/domain/branch_service.dart` (+ `fetch`), `data/services/git_branch_service.dart`, `lib/core/di/injection_container.dart`
- Test: `test/features/collections/data/services/git_conflict_service_test.dart`

**Interfaces consumed:** `GitService` (Task 1), `ThreeWayMerge` (Task 2), `ConflictService`+entities (Task 3), `WorkspaceCollectionSerializer` (existing).

Key logic:
```dart
class GitConflictService implements ConflictService {
  GitConflictService(this._git);
  final GitService _git;

  @override
  Future<PullOutcome> pullOrConflict(String root) => _git.pull(root);

  @override
  Future<RebaseStep> continueRebase(String root) async {
    await _git.rebaseContinue(root);
    return await _git.isRebaseInProgress(root)
        ? RebaseStep.moreConflicts : RebaseStep.done;
  }

  @override
  Future<void> abort(String root) => _git.rebaseAbort(root);
  @override
  Future<void> fetch(String root) => _git.fetch(root);

  @override
  Future<List<FileConflict>> currentConflicts(String root) async {
    final paths = await _git.conflictedPaths(root);
    return [for (final p in paths) await _classify(root, p)];
  }

  Future<FileConflict> _classify(String root, String path) async {
    final s1 = await _git.showStage(root, path, 1);
    final s2 = await _git.showStage(root, path, 2); // incoming
    final s3 = await _git.showStage(root, path, 3); // yours
    if (path.endsWith('.req.json')) {
      // delete/modify: one side stage missing
      if (s2 == null || s3 == null) {
        return FileConflict(path: path, kind: ConflictKind.deleteModify);
      }
      final base = _leafOrNull(s1), inc = _leafOrNull(s2), you = _leafOrNull(s3);
      if (inc == null || you == null) {
        return FileConflict(path: path, kind: ConflictKind.structural); // unparseable
      }
      final node = ThreeWayMerge.mergeRequest(base, inc, you);
      return FileConflict(path: path,
        kind: s1 == null ? ConflictKind.addAdd : ConflictKind.request, node: node);
    }
    if (path.endsWith('.folder.json')) { /* symmetric with mergeFolder */ }
    return FileConflict(path: path, kind: ConflictKind.structural); // workspace.json etc.
  }

  @override
  Future<void> resolve(String root, List<FileResolution> resolutions) async {
    for (final res in resolutions) {
      final content = await _resolvedContent(root, res); // apply picks → JSON string
      await _git.writeWorkingFile(root, res.path, content);
      await _git.add(root, res.path);
    }
  }
  // _resolvedContent: coarse → showStage(incoming|yours); field-level → rebuild the
  // merged node applying res.fieldChoices, serialize via WorkspaceCollectionSerializer.
}
```
`BranchService.fetch(String root)` → `GitBranchService`: **no** `_runOnTree` (fetch never touches the working tree), just `_git.fetch(root)`. Register `ConflictService` in DI: `sl.registerLazySingleton<ConflictService>(() => GitConflictService(sl()))`.

- [ ] Steps: failing tests (mock `GitService`: classify req/folder/deleteModify/structural; resolve writes merged JSON + adds; continueRebase maps `isRebaseInProgress`) → run-fail → implement → green → gate → commit `feat(collections): GitConflictService + BranchService.fetch + DI`.

---

## Task 5: `ConflictBloc` (+ event/state) + DI

**Files:**
- Create: `lib/features/collections/presentation/bloc/conflict_bloc.dart` / `_event.dart` / `_state.dart`
- Modify: `lib/core/di/injection_container.dart`
- Test: `test/features/collections/presentation/bloc/conflict_bloc_test.dart`

**Interfaces produced:**
```dart
// events: LoadConflicts(root) ; ResolveAndContinue(root, List<FileResolution>) ; AbortRebase(root)
// state:
enum ConflictStatus { initial, loading, resolving, done, error }
class ConflictState extends Equatable {
  const ConflictState({this.status = ConflictStatus.initial,
    this.conflicts = const [], this.batch = 0, this.errorMessage});
  final ConflictStatus status;
  final List<FileConflict> conflicts;  // current batch
  final int batch;                     // 0-based commit index, for "commit N"
  final String? errorMessage;
  bool get isBusy => status == ConflictStatus.loading || status == ConflictStatus.resolving;
  // copyWith clears errorMessage unless status==error (mirror PullRequestsState).
}
```
Behaviour (mirror `GitSyncBloc`/`PullRequestsBloc` conventions — droppable-while-busy, terminal on every path, `log` via `dart:developer`):
- `LoadConflicts` → `currentConflicts(root)` → ready with the batch (or `done` if empty).
- `ResolveAndContinue` → `resolve(root, res)` → `continueRebase(root)` → `moreConflicts` ? reload `currentConflicts` (bump `batch`) : `done`. Any throw → `error` (leave paused).
- `AbortRebase` → `abort(root)` → `done`.

- [ ] Steps: failing bloc tests (load populates; resolve→continue→done; resolve→continue→moreConflicts loads next batch, **Completer-gated non-vacuous** that the next `currentConflicts` runs only after `continueRebase`; abort→done; error surfaces) → run-fail → implement → green → gate + `feat(collections): ConflictBloc` (bloc_lint must pass).

---

## Task 6: `ConflictResolutionDialog` + pull-flow wiring + fetch UI

**Files:**
- Create: `lib/features/collections/presentation/widgets/conflict_resolution_dialog.dart`
- Modify: `branch_chip.dart` (FETCH item + auto-fetch timer + open resolver on conflicted pull), `git_sync_event.dart` (`FetchRemote`), `git_sync_bloc.dart` (`FetchRemote` handler; pull now returns `PullOutcome` and, when conflicted, signals the widget to open the resolver), `lib/main.dart` (provide `ConflictBloc`)
- Test: `test/features/collections/presentation/widgets/conflict_resolution_dialog_test.dart`

**Dialog** (`ConflictResolutionDialog.show(context, {required String root})`), following `stash_list_dialog.dart` + `pull_requests_dialog.dart` patterns (`showResponsiveDialog` + `ResponsiveDialogScaffold`, blocs re-provided via `.value`, `context.appLayout/appTypography/appPalette` — no hardcoded sizes/colors):
- `initState` dispatches `LoadConflicts(root)`.
- Body: header "Resolving conflicts — commit ${batch+1}"; a list of `FileConflict` rows.
  - Field-level file: expand to its `node.conflicts`; each row shows the field label, **Take Incoming** / **Keep Yours** segmented control (+ an **Edit** affordance for `scalar` kind opening a text field; `body` label → the JSON editor via `createJsonCodeController`). Opaque (`auth`/list) rows show only the two buttons, no values. Auto-merged files (empty `node.conflicts`) render a muted "auto-merged" row (no action).
  - Coarse file (`addAdd`/`deleteModify`/`structural`): two choices — `deleteModify` labelled **"Keep your edited request" / "Accept the deletion"**; else **Take Incoming / Keep Yours**.
- Footer: **CANCEL** → `AbortRebase` + close; **RESOLVE & CONTINUE** (enabled only when every conflict has a pick) → build `List<FileResolution>` + dispatch `ResolveAndContinue`.
- `BlocListener`: `done` → close + snackbar "Conflicts resolved."; `error` → GIT ERROR dialog (leave open); when `moreConflicts` reloads, the list just rebuilds with the next batch.

**Pull-flow wiring:** `GitSyncBloc._onPull` awaits `_service.pull` which now returns `PullOutcome`. On `conflicted`, emit a state flag (add `bool pullConflicted` or reuse a dedicated `GitSyncStatus`); `BranchChip`'s `BlocListener` on that flag opens `ConflictResolutionDialog.show(context, root:)`. (No bloc→bloc: the chip widget holds both blocs.) `BranchService.pull` return type changes to `Future<PullOutcome>`; `GitBranchService.pull` returns `_runOnTree`'s result — adjust `_runOnTree` to be generic `Future<T>` or add a `_runOnTreeValue`.

**Fetch UI:** `FetchRemote(root)` event → `GitSyncBloc._onFetch` = `_run(root, emit, 'fetch', () => _service.fetch(root))` (no `changedDisk`). Branch-chip menu: add `PopupMenuItem(value: 'fetch', enabled: branch.hasRemote, child: Text(branch.hasRemote ? 'FETCH' : 'FETCH — NO REMOTE'))` and `case 'fetch': bloc.add(FetchRemote(root));`. Auto-fetch: in `_BranchChipState`, add a `Timer.periodic(const Duration(minutes: 5), ...)` started in `initState` (guarded by `!kIsWeb`) + one fetch on first workspace resolution; each tick reads root from `SettingsBloc` and, if a remote exists, dispatches `FetchRemote`; cancel the timer in `dispose`. Auto-fetch failures already land in `GitSyncState.errorMessage` — but to avoid a nagging dialog when offline, the chip's error listener should **not** pop a dialog for a fetch failure (gate the existing error listener so only user-initiated ops show the GIT ERROR dialog; simplest: a `bool _userAction` flag set on menu actions, or ignore errors whose op was a fetch by tracking the last dispatched op).

- [ ] Steps: failing widget tests (field row renders Take Incoming/Keep Yours; coarse deleteModify labels; RESOLVE disabled until all picked; CANCEL dispatches AbortRebase; FETCH menu item dispatches FetchRemote; blocs built inside the test body with `brutalistTheme`) → run-fail → implement → green → **full done-bar** → commit `feat(git): conflict resolution dialog + fetch action`.

---

## Task 7: Full gate + wiki + final review

- [ ] **Step 1:** Run the complete done-bar (all six gates) — fix anything.
- [ ] **Step 2: Wiki** — on the `Version-Control.md` page (Getman.wiki, push over SSH): add a **Resolving conflicts** section (pull pauses on conflict → per-field Take Incoming/Keep Yours → RESOLVE & CONTINUE loops per commit → CANCEL aborts; only open PRs... n/a; describe auto-merge) and a **Fetch** note (auto-fetch keeps ahead/behind fresh; manual **FETCH** in the branch menu). Update "Requirements at a glance" if needed. Commit + push.
- [ ] **Step 3: Final whole-branch adversarial review** over `git diff <spec-C-head>..HEAD` (exclude docs): the rebase ours/theirs swap, auto-merge correctness, resolve→continue loop can't wedge or lose data, cancel always aborts, non-interactive git (no editor block), auto-fetch swallows offline errors + never auto-pulls, web-safety, layering, test non-vacuity. Fix Critical/Important.
- [ ] **Step 4:** Update the roadmap memory (Spec D done) + ledger.

---

## Self-Review

- **Spec coverage:** entry flow (T1 pull outcome + T6 wiring), field/file scope (T2 merge + T4 classify), 3-way auto-merge (T2), stage reads (T1), rebase-swap labelling (T2/T6, called out in Global Constraints), fetch auto+manual (T4/T6), structural (T4 classify + T6 coarse rows), error handling (T1 pull throw-on-non-conflict, T5 leave-paused, T6 fetch-error-silent), mirror suspension (reused via `_runOnTree` in T4/existing), testing (each task), wiki (T7). All covered.
- **Type consistency:** `PullOutcome` (T1) used in T4/T6; `NodeMergeResult`/`FieldConflict` (T2) in T3/T4/T6; `FileConflict`/`FileResolution`/`RebaseStep` (T3) in T4/T5/T6; `ConflictService` methods consistent across T3/T4/T5.
- **Placeholders:** the folder-classify and `_resolvedContent` bodies are described by rule (symmetric to the request path) rather than fully spelled — the implementer mirrors the request branch; acceptable given the request branch is fully shown.

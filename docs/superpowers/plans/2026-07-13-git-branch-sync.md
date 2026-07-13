# Git Branch & Sync (Spec B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the git-backed collections workspace collaborative — list/switch/create branches, pull, push, and stash from a branch chip in the collections header, reloading the tree from disk whenever git changes the files underneath the app.

**Architecture:** Three layers, mirroring Spec A. `GitService` (`lib/core/git/`, the sole `dart:io` importer, web-stubbed) gains branch/sync/stash primitives. A domain `BranchService` abstraction wraps it, and `GitSyncBloc` depends only on that abstraction (required by the `bloc_depends_on_abstractions` custom_lint rule). The tree reload after a switch/pull is done by a widget-layer coordinator (`BranchSyncListener`), never bloc→bloc.

**Tech Stack:** Flutter, flutter_bloc, get_it, equatable, mocktail, bloc_test, `Process.run('git', ...)` (no shell → no injection).

**Spec:** `docs/superpowers/specs/2026-07-13-git-branch-sync-design.md`

## Global Constraints

- Always invoke Flutter as `fvm flutter ...` / `fvm dart ...`. Never plain `flutter`.
- **Done-bar (all must be clean, they are separate passes):** `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `( cd tools/getman_lints/example && fvm dart run custom_lint )`, `fvm dart format lib test tools`, and a 100% green `fvm flutter test`. Run analyze over the **whole repo**, not just the files you touched — test-file lint counts.
- **`dart:io` only in `*_io.dart` files** (enforced by the `platform_io_outside_io_files` lint). `git_service_io.dart` is the only place git is executed.
- **Blocs must not import `data/`** (enforced by `bloc_depends_on_abstractions`). `GitSyncBloc` depends on the domain `BranchService` abstraction only.
- **No bloc→bloc coupling.** Cross-bloc coordination happens in a widget that holds both (see `WorkspaceSyncListener`, `ChainingWriteBackListener`).
- **No `GetIt`/`sl<T>()` in widgets** (`avoid_get_it_in_widgets`). Widgets reach services via `BlocProvider` / `RepositoryProvider`.
- **No hardcoded sizes/colors/radii/weights** in widgets — read `context.appLayout`, `context.appPalette`, `context.appShape`, `context.appTypography`, `context.appDecoration`. No `Colors.black/white/red` literals (`avoid_hardcoded_brand_colors`).
- **Blocs log with `dart:developer`'s `log(msg, name: '<BlocName>')`**, never `debugPrint` (a `package:flutter/foundation.dart` import in a bloc trips bloc_lint).
- **Every `Equatable` class lists all its fields in `props`** (`equatable_props_complete`).
- Imports are `package:getman/...` — no relative imports; directives sorted alphabetically.
- Getman **stores no credentials** and never edits the user's git config. Auth is whatever the user's SSH agent / credential helper already does.
- Lines ≤ 80 chars.

---

## File Structure

**Create:**
- `lib/features/collections/domain/entities/branch_status.dart` — `BranchStatus`, `StashEntry`, `AheadBehind`
- `lib/features/collections/domain/branch_service.dart` — abstract `BranchService`
- `lib/features/collections/data/services/git_branch_service.dart` — `GitBranchService implements BranchService`
- `lib/features/collections/presentation/bloc/git_sync_bloc.dart` / `git_sync_event.dart` / `git_sync_state.dart`
- `lib/features/collections/presentation/widgets/branch_chip.dart` — the header chip + menu
- `lib/features/collections/presentation/widgets/stash_list_dialog.dart`
- `lib/features/collections/presentation/widgets/branch_sync_listener.dart` — reload coordinator

**Modify:**
- `lib/core/git/git_service.dart` (abstract + entities), `git_service_io.dart`, `git_service_stub.dart`
- `lib/features/collections/data/services/workspace_sync_service.dart` — `flushPending()`
- `lib/features/collections/presentation/widgets/collections_list.dart` — mount the chip
- `lib/core/di/injection_container.dart`, `lib/main.dart` — register + provide

---

### Task 1: GitService — branch primitives

**Files:**
- Modify: `lib/core/git/git_service.dart`
- Modify: `lib/core/git/git_service_io.dart`
- Modify: `lib/core/git/git_service_stub.dart`
- Test: `test/core/git/git_service_io_test.dart`

**Interfaces:**
- Consumes: existing `GitService` (`isAvailable`, `isRepo`, `init`, `currentBranch`, `status`, `headContent`, `workingContent`, `stage`, `unstage`, `commit`), `GitException`.
- Produces: `class AheadBehind { final int ahead; final int behind; }`; `GitService.branches(String root) → Future<List<String>>`, `createBranch(String root, String name)`, `switchBranch(String root, String name)`, `hasRemote(String root) → Future<bool>`, `aheadBehind(String root) → Future<AheadBehind>`.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` in `test/core/git/git_service_io_test.dart` (the existing
`setUp` already creates a temp repo and configures `user.email`/`user.name`;
`gitPresent()` is the existing skip guard):

```dart
  // Commits a file so the repo has a HEAD (a repo with no commits has no
  // branch to branch from).
  Future<void> seedCommit() async {
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":1}');
    await git.stage(tmp.path, ['a.req.json']);
    await git.commit(tmp.path, 'seed');
  }

  test('branches lists local branches; createBranch switches to it', () async {
    if (!await gitPresent()) return;
    await seedCommit();

    await git.createBranch(tmp.path, 'feat/x');

    expect(await git.currentBranch(tmp.path), 'feat/x');
    expect(await git.branches(tmp.path), contains('feat/x'));
  });

  test('switchBranch moves between existing branches', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    final initial = (await git.currentBranch(tmp.path))!;
    await git.createBranch(tmp.path, 'feat/x');

    await git.switchBranch(tmp.path, initial);

    expect(await git.currentBranch(tmp.path), initial);
  });

  test('hasRemote is false without a remote', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    expect(await git.hasRemote(tmp.path), isFalse);
  });

  test('aheadBehind is (0,0) when the branch has no upstream', () async {
    if (!await gitPresent()) return;
    await seedCommit();

    final ab = await git.aheadBehind(tmp.path);

    expect(ab.ahead, 0);
    expect(ab.behind, 0);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/core/git/git_service_io_test.dart`
Expected: FAIL — the methods `branches`/`createBranch`/`switchBranch`/`hasRemote`/`aheadBehind` are not defined on `GitService`.

- [ ] **Step 3: Add the entity + abstract methods**

In `lib/core/git/git_service.dart`, add above `abstract class GitService`:

```dart
/// Commits the current branch is ahead of / behind its upstream. Both are 0
/// when the branch has no upstream (a brand-new local branch is normal, not an
/// error).
class AheadBehind {
  const AheadBehind({required this.ahead, required this.behind});
  final int ahead;
  final int behind;

  static const none = AheadBehind(ahead: 0, behind: 0);
}
```

and inside `abstract class GitService`:

```dart
  /// Local branch names.
  Future<List<String>> branches(String root);

  /// Creates [name] and switches to it (`git switch -c`).
  Future<void> createBranch(String root, String name);

  /// Switches to an existing branch. Throws [GitException] when git refuses
  /// (e.g. the checkout would clobber local changes).
  Future<void> switchBranch(String root, String name);

  /// Whether the repo has at least one remote configured.
  Future<bool> hasRemote(String root);

  /// Ahead/behind counts vs the current branch's upstream.
  Future<AheadBehind> aheadBehind(String root);
```

- [ ] **Step 4: Implement in the io service**

In `lib/core/git/git_service_io.dart`, add to `_IoGitService`:

```dart
  @override
  Future<List<String>> branches(String root) async {
    final r = await _run(root, [
      'branch',
      '--format=%(refname:short)',
    ]);
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Future<void> createBranch(String root, String name) async {
    await _run(root, ['switch', '-c', name]);
  }

  @override
  Future<void> switchBranch(String root, String name) async {
    await _run(root, ['switch', name]);
  }

  @override
  Future<bool> hasRemote(String root) async {
    final r = await _run(root, ['remote'], allowFailure: true);
    return (r.stdout as String).trim().isNotEmpty;
  }

  @override
  Future<AheadBehind> aheadBehind(String root) async {
    // `@{u}...HEAD` prints "<behind>\t<ahead>". Exits non-zero when the branch
    // has no upstream — that is a normal state, so report (0, 0).
    final r = await _run(root, [
      'rev-list',
      '--left-right',
      '--count',
      '@{u}...HEAD',
    ], allowFailure: true);
    if (r.exitCode != 0) return AheadBehind.none;
    final parts = (r.stdout as String).trim().split(RegExp(r'\s+'));
    if (parts.length != 2) return AheadBehind.none;
    return AheadBehind(
      behind: int.tryParse(parts[0]) ?? 0,
      ahead: int.tryParse(parts[1]) ?? 0,
    );
  }
```

- [ ] **Step 5: Implement in the web stub**

In `lib/core/git/git_service_stub.dart`, add to `_StubGitService`:

```dart
  @override
  Future<List<String>> branches(String root) async => const [];
  @override
  Future<void> createBranch(String root, String name) async {}
  @override
  Future<void> switchBranch(String root, String name) async {}
  @override
  Future<bool> hasRemote(String root) async => false;
  @override
  Future<AheadBehind> aheadBehind(String root) async => AheadBehind.none;
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `fvm flutter test test/core/git/git_service_io_test.dart`
Expected: PASS (all tests, including the pre-existing ones).

- [ ] **Step 7: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint`
Expected: no issues from either pass.

```bash
git add lib/core/git test/core/git
git commit -m "feat(git): branch list/create/switch + ahead-behind in GitService"
```

---

### Task 2: GitService — pull & push (against a local bare remote)

**Files:**
- Modify: `lib/core/git/git_service.dart`
- Modify: `lib/core/git/git_service_io.dart`
- Modify: `lib/core/git/git_service_stub.dart`
- Test: `test/core/git/git_sync_io_test.dart` (new file — the sync tests need a
  bare-repo fixture the existing file does not have)

**Interfaces:**
- Consumes: Task 1's `GitService` (incl. `aheadBehind`, `hasRemote`).
- Produces: `GitService.pull(String root)`, `GitService.push(String root, {required bool setUpstream})`, `GitService.hasUpstream(String root) → Future<bool>`.

A conflicting pull must **abort the rebase** so the working tree is left byte-identical to its prior state. This is the single most important behavior in this task.

- [ ] **Step 1: Write the failing tests**

Create `test/core/git/git_sync_io_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';

void main() {
  late GitService git;
  late Directory remote; // bare repo standing in for origin — no network
  late Directory a; // clone A (the "app")
  late Directory b; // clone B (a teammate)

  Future<void> run(String dir, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
    }
  }

  Future<void> identify(String dir) async {
    await run(dir, ['config', 'user.email', 't@t.dev']);
    await run(dir, ['config', 'user.name', 'T']);
  }

  Future<void> commitFile(String dir, String name, String content) async {
    File('$dir/$name').writeAsStringSync(content);
    await run(dir, ['add', '--', name]);
    await run(dir, ['commit', '-m', 'change $name']);
  }

  Future<bool> gitPresent() async => git.isAvailable();

  setUp(() async {
    git = createGitService();
    remote = await Directory.systemTemp.createTemp('getman_remote');
    a = await Directory.systemTemp.createTemp('getman_a');
    b = await Directory.systemTemp.createTemp('getman_b');
    if (!await gitPresent()) return;

    await run(remote.path, ['init', '--bare', '--initial-branch=main']);

    // Seed clone A and publish an initial commit.
    await run(a.path, ['init', '--initial-branch=main']);
    await identify(a.path);
    await run(a.path, ['remote', 'add', 'origin', remote.path]);
    await commitFile(a.path, 'a.req.json', '{"v":1}');
    await run(a.path, ['push', '-u', 'origin', 'main']);

    // Clone B from the same bare repo.
    await run(b.path, ['clone', remote.path, '.']);
    await identify(b.path);
  });

  tearDown(() async {
    for (final d in [remote, a, b]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  test('hasRemote is true for a cloned repo', () async {
    if (!await gitPresent()) return;
    expect(await git.hasRemote(a.path), isTrue);
  });

  test('push publishes local commits; the remote advances', () async {
    if (!await gitPresent()) return;
    await commitFile(a.path, 'b.req.json', '{"v":2}');
    expect((await git.aheadBehind(a.path)).ahead, 1);

    await git.push(a.path, setUpstream: false);

    expect((await git.aheadBehind(a.path)).ahead, 0);
  });

  test('push with setUpstream publishes a brand-new branch', () async {
    if (!await gitPresent()) return;
    await git.createBranch(a.path, 'feat/x');
    await commitFile(a.path, 'c.req.json', '{"v":3}');
    expect(await git.hasUpstream(a.path), isFalse);

    await git.push(a.path, setUpstream: true);

    expect(await git.hasUpstream(a.path), isTrue);
  });

  test('pull rebases the teammate commit into the local branch', () async {
    if (!await gitPresent()) return;
    // Teammate publishes a change.
    await commitFile(b.path, 'teammate.req.json', '{"v":9}');
    await run(b.path, ['push', 'origin', 'main']);
    await run(a.path, ['fetch', 'origin']);

    await git.pull(a.path);

    expect(File('${a.path}/teammate.req.json').existsSync(), isTrue);
  });

  test('a conflicting pull aborts and leaves the tree untouched', () async {
    if (!await gitPresent()) return;
    // Both sides edit the same file differently.
    await commitFile(b.path, 'a.req.json', '{"v":"theirs"}');
    await run(b.path, ['push', 'origin', 'main']);
    await commitFile(a.path, 'a.req.json', '{"v":"mine"}');

    await expectLater(
      git.pull(a.path),
      throwsA(isA<GitException>()),
    );

    // The abort must restore the pre-pull state exactly: our content is intact,
    // no conflict markers, no rebase in progress, and the tree is clean.
    expect(File('${a.path}/a.req.json').readAsStringSync(), '{"v":"mine"}');
    expect(await git.status(a.path), isEmpty);
    expect(Directory('${a.path}/.git/rebase-merge').existsSync(), isFalse);
    expect(Directory('${a.path}/.git/rebase-apply').existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/core/git/git_sync_io_test.dart`
Expected: FAIL — `pull`, `push`, `hasUpstream` are not defined on `GitService`.

- [ ] **Step 3: Add the abstract methods**

In `lib/core/git/git_service.dart`, inside `abstract class GitService`:

```dart
  /// Whether the current branch has an upstream configured.
  Future<bool> hasUpstream(String root);

  /// `git pull --rebase`. On conflict the rebase is **aborted** before throwing,
  /// so a failed pull leaves the working tree exactly as it was — Getman has no
  /// conflict-resolution UI yet (Spec D).
  Future<void> pull(String root);

  /// Pushes the current branch. Pass [setUpstream] for a branch that has never
  /// been pushed (`git push -u origin <branch>`).
  Future<void> push(String root, {required bool setUpstream});
```

- [ ] **Step 4: Implement in the io service**

In `lib/core/git/git_service_io.dart`, add to `_IoGitService`:

```dart
  @override
  Future<bool> hasUpstream(String root) async {
    final r = await _run(root, [
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ], allowFailure: true);
    return r.exitCode == 0;
  }

  @override
  Future<void> pull(String root) async {
    final r = await _run(root, ['pull', '--rebase'], allowFailure: true);
    if (r.exitCode == 0) return;
    // Leave no half-rebased tree behind: undo it, then report the failure.
    await _run(root, ['rebase', '--abort'], allowFailure: true);
    final err = (r.stderr as String).trim();
    throw GitException(
      err.isEmpty ? 'git pull failed' : err,
      exitCode: r.exitCode,
    );
  }

  @override
  Future<void> push(String root, {required bool setUpstream}) async {
    final branch = await currentBranch(root);
    if (branch == null) throw GitException('no current branch to push');
    await _run(root, [
      'push',
      if (setUpstream) '-u',
      if (setUpstream) 'origin',
      if (setUpstream) branch,
    ]);
  }
```

- [ ] **Step 5: Implement in the web stub**

In `lib/core/git/git_service_stub.dart`, add to `_StubGitService`:

```dart
  @override
  Future<bool> hasUpstream(String root) async => false;
  @override
  Future<void> pull(String root) async {}
  @override
  Future<void> push(String root, {required bool setUpstream}) async {}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `fvm flutter test test/core/git`
Expected: PASS — including `a conflicting pull aborts and leaves the tree untouched`.

- [ ] **Step 7: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint`

```bash
git add lib/core/git test/core/git
git commit -m "feat(git): pull --rebase (abort on conflict) + push with upstream"
```

---

### Task 3: GitService — stash

**Files:**
- Modify: `lib/core/git/git_service.dart`
- Modify: `lib/core/git/git_service_io.dart`
- Modify: `lib/core/git/git_service_stub.dart`
- Test: `test/core/git/git_service_io_test.dart`

**Interfaces:**
- Consumes: Task 1's `GitService`.
- Produces: `class StashEntry { final int index; final String message; }`; `GitService.stashList(String root) → Future<List<StashEntry>>`, `stashPush(String root, String message)`, `stashPop(String root, int index)`, `stashDrop(String root, int index)`.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` in `test/core/git/git_service_io_test.dart` (reuse the
`seedCommit()` helper added in Task 1):

```dart
  test('stashPush clears the working tree; pop restores it', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":2}');

    await git.stashPush(tmp.path, 'wip');
    expect(await git.status(tmp.path), isEmpty);
    expect(File('${tmp.path}/a.req.json').readAsStringSync(), '{"x":1}');

    final stashes = await git.stashList(tmp.path);
    expect(stashes.single.index, 0);
    expect(stashes.single.message, contains('wip'));

    await git.stashPop(tmp.path, 0);
    expect(File('${tmp.path}/a.req.json').readAsStringSync(), '{"x":2}');
    expect(await git.stashList(tmp.path), isEmpty);
  });

  test('stashPush includes untracked files', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    File('${tmp.path}/new.req.json').writeAsStringSync('{"n":1}');

    await git.stashPush(tmp.path, 'wip');

    // -u: an untracked new request must be stashed too, or a "stash and switch"
    // would carry it onto the target branch.
    expect(File('${tmp.path}/new.req.json').existsSync(), isFalse);
  });

  test('stashDrop removes a stash without restoring it', () async {
    if (!await gitPresent()) return;
    await seedCommit();
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":3}');
    await git.stashPush(tmp.path, 'wip');

    await git.stashDrop(tmp.path, 0);

    expect(await git.stashList(tmp.path), isEmpty);
    expect(File('${tmp.path}/a.req.json').readAsStringSync(), '{"x":1}');
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/core/git/git_service_io_test.dart`
Expected: FAIL — `stashPush`/`stashList`/`stashPop`/`stashDrop` are not defined.

- [ ] **Step 3: Add the entity + abstract methods**

In `lib/core/git/git_service.dart`, add above `abstract class GitService`:

```dart
/// One entry of `git stash list`. [index] is its position (`stash@{index}`).
class StashEntry {
  const StashEntry({required this.index, required this.message});
  final int index;
  final String message;
}
```

and inside `abstract class GitService`:

```dart
  Future<List<StashEntry>> stashList(String root);

  /// Stashes tracked *and* untracked changes (`git stash push -u`), so a
  /// stash-then-switch does not carry a new request onto the target branch.
  Future<void> stashPush(String root, String message);

  Future<void> stashPop(String root, int index);
  Future<void> stashDrop(String root, int index);
```

- [ ] **Step 4: Implement in the io service**

In `lib/core/git/git_service_io.dart`, add to `_IoGitService`:

```dart
  @override
  Future<List<StashEntry>> stashList(String root) async {
    final r = await _run(root, ['stash', 'list', '--format=%gs']);
    final lines = (r.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return [
      for (var i = 0; i < lines.length; i++)
        StashEntry(index: i, message: lines[i].trim()),
    ];
  }

  @override
  Future<void> stashPush(String root, String message) async {
    await _run(root, ['stash', 'push', '-u', '-m', message]);
  }

  @override
  Future<void> stashPop(String root, int index) async {
    await _run(root, ['stash', 'pop', 'stash@{$index}']);
  }

  @override
  Future<void> stashDrop(String root, int index) async {
    await _run(root, ['stash', 'drop', 'stash@{$index}']);
  }
```

- [ ] **Step 5: Implement in the web stub**

In `lib/core/git/git_service_stub.dart`, add to `_StubGitService`:

```dart
  @override
  Future<List<StashEntry>> stashList(String root) async => const [];
  @override
  Future<void> stashPush(String root, String message) async {}
  @override
  Future<void> stashPop(String root, int index) async {}
  @override
  Future<void> stashDrop(String root, int index) async {}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `fvm flutter test test/core/git`
Expected: PASS.

- [ ] **Step 7: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint`

```bash
git add lib/core/git test/core/git
git commit -m "feat(git): stash push/list/pop/drop in GitService"
```

---

### Task 4: WorkspaceSyncService.flushPending — close the debounce race

**Files:**
- Modify: `lib/features/collections/data/services/workspace_sync_service.dart`
- Test: `test/features/collections/data/services/workspace_sync_service_test.dart`

**Interfaces:**
- Consumes: existing `WorkspaceSyncService(dataSource, {debounce})` with `scheduleMirror(root, forest)`, `read(root)`, `mirrored` (a broadcast `Stream<String>` emitting the root after each successful write), `dispose()`.
- Produces: `Future<void> flushPending()` — cancels the pending debounce timer and runs the pending write to completion; a no-op when nothing is pending.

**Why:** the mirror is debounced by 1 second. Edit a request, click "switch branch" within that window, and `git status` sees a *clean* tree (the write has not landed) — we check out, and the timer then writes the edited request onto the **new branch**. Every mutating git action must flush first.

- [ ] **Step 1: Write the failing test**

Add inside `main()` in `test/features/collections/data/services/workspace_sync_service_test.dart` (`ds` is the existing `_MockDataSource`, already stubbed in `setUp`):

```dart
  test('flushPending writes a pending mirror immediately', () async {
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(seconds: 30), // would not fire on its own
    );
    addTearDown(service.dispose);

    service.scheduleMirror('/ws', const []);
    verifyNever(() => ds.write('/ws', any()));

    await service.flushPending();

    // The write must have landed *before* flushPending completes — this is what
    // lets a branch switch trust `git status`.
    verify(() => ds.write('/ws', any())).called(1);
  });

  test('flushPending is a no-op when nothing is pending', () async {
    final service = WorkspaceSyncService(ds);
    addTearDown(service.dispose);

    await service.flushPending();

    verifyNever(() => ds.write(any(), any()));
  });

  test('flushPending does not write twice when the timer also fires', () async {
    final service = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    service.scheduleMirror('/ws', const []);
    await service.flushPending();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    verify(() => ds.write('/ws', any())).called(1);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/features/collections/data/services/workspace_sync_service_test.dart`
Expected: FAIL — `flushPending` is not defined.

- [ ] **Step 3: Implement flushPending**

In `lib/features/collections/data/services/workspace_sync_service.dart`, hold the
pending write's arguments alongside the timer and expose the flush. Replace the
`_timer` field and `scheduleMirror` with:

```dart
  Timer? _timer;
  String? _pendingRoot;
  List<CollectionNodeEntity>? _pendingForest;

  /// Debounced Hive → disk mirror. Coalesces bursts of mutations into one
  /// write.
  void scheduleMirror(String root, List<CollectionNodeEntity> forest) {
    _timer?.cancel();
    _pendingRoot = root;
    _pendingForest = forest;
    _timer = Timer(debounce, () {
      final r = _pendingRoot;
      final f = _pendingForest;
      _pendingRoot = null;
      _pendingForest = null;
      if (r == null || f == null) return;
      unawaited(_mirror(r, f));
    });
  }

  /// Runs any pending debounced write to completion, now.
  ///
  /// Callers that read the mirrored files through git (branch switch, pull,
  /// push, stash) MUST await this first: otherwise a write scheduled moments
  /// earlier has not landed, `git status` reports a clean tree, and the timer
  /// fires *after* the checkout — writing the user's edit onto the branch they
  /// switched to.
  Future<void> flushPending() async {
    _timer?.cancel();
    _timer = null;
    final root = _pendingRoot;
    final forest = _pendingForest;
    _pendingRoot = null;
    _pendingForest = null;
    if (root == null || forest == null) return;
    await _mirror(root, forest);
  }
```

Keep `_mirror`, `mirrored`, `_quietedRoots`, and `dispose()` as they are.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/features/collections/data/services/workspace_sync_service_test.dart`
Expected: PASS (including the pre-existing debounce/mirrored tests).

- [ ] **Step 5: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint`

```bash
git add lib/features/collections/data/services/workspace_sync_service.dart \
        test/features/collections/data/services/workspace_sync_service_test.dart
git commit -m "feat(collections): flushPending on WorkspaceSyncService"
```

---

### Task 5: Domain BranchService + GitBranchService

**Files:**
- Create: `lib/features/collections/domain/entities/branch_status.dart`
- Create: `lib/features/collections/domain/branch_service.dart`
- Create: `lib/features/collections/data/services/git_branch_service.dart`
- Modify: `lib/core/di/injection_container.dart`
- Test: `test/features/collections/data/services/git_branch_service_test.dart`

**Interfaces:**
- Consumes: `GitService` (Tasks 1–3), `WorkspaceSyncService.flushPending()` (Task 4). `StashEntry` is re-exported from the domain entity file so the bloc/UI never import `core/git` types indirectly — actually the domain entity file **defines its own** `StashEntry` (see below) to keep the domain free of infrastructure types.
- Produces:
  - `BranchStatus` (Equatable): `{String? current, List<String> branches, int ahead, int behind, bool hasRemote, bool isRepo, List<StashInfo> stashes}` + `int get stashCount`.
  - `StashInfo` (Equatable): `{int index, String message}`.
  - abstract `BranchService`: `status(root)`, `isDirty(root)`, `switchTo(root, branch)`, `create(root, branch)`, `pull(root)`, `push(root)`, `stash(root, message)`, `popStash(root, index)`, `dropStash(root, index)`.
  - `GitBranchService(GitService, WorkspaceSyncService) implements BranchService`.

Note the domain layer must not import `dart:io`/`data/` (`domain_no_infrastructure_imports`). `core/git/git_service.dart` is pure Dart (its `dart:io` lives behind the conditional export), so importing it from `data/` is fine; the **domain** entity defines its own `StashInfo` rather than reusing `StashEntry`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/collections/data/services/git_branch_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/git_branch_service.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:mocktail/mocktail.dart';

class _MockGit extends Mock implements GitService {}

class _MockDataSource extends Mock
    implements WorkspaceCollectionsDataSource {}

void main() {
  const root = '/ws';
  late _MockGit git;
  late _MockDataSource ds;
  late WorkspaceSyncService sync;
  late GitBranchService service;

  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  setUp(() {
    git = _MockGit();
    ds = _MockDataSource();
    when(() => ds.write(any(), any())).thenAnswer((_) async {});
    sync = WorkspaceSyncService(ds, debounce: const Duration(seconds: 30));
    service = GitBranchService(git, sync);

    when(() => git.isAvailable()).thenAnswer((_) async => true);
    when(() => git.isRepo(root)).thenAnswer((_) async => true);
    when(() => git.currentBranch(root)).thenAnswer((_) async => 'main');
    when(() => git.branches(root)).thenAnswer((_) async => ['main', 'feat/x']);
    when(() => git.hasRemote(root)).thenAnswer((_) async => true);
    when(
      () => git.aheadBehind(root),
    ).thenAnswer((_) async => const AheadBehind(ahead: 2, behind: 1));
    when(() => git.stashList(root)).thenAnswer(
      (_) async => const [StashEntry(index: 0, message: 'WIP on main')],
    );
    when(() => git.status(root)).thenAnswer((_) async => const []);
    when(() => git.switchBranch(root, any())).thenAnswer((_) async {});
    when(() => git.createBranch(root, any())).thenAnswer((_) async {});
    when(() => git.stashPush(root, any())).thenAnswer((_) async {});
    when(() => git.pull(root)).thenAnswer((_) async {});
    when(() => git.push(root, setUpstream: any(named: 'setUpstream')))
        .thenAnswer((_) async {});
    when(() => git.hasUpstream(root)).thenAnswer((_) async => true);
  });

  tearDown(sync.dispose);

  test('status maps git state into BranchStatus', () async {
    final s = await service.status(root);

    expect(s.current, 'main');
    expect(s.branches, ['main', 'feat/x']);
    expect(s.ahead, 2);
    expect(s.behind, 1);
    expect(s.hasRemote, isTrue);
    expect(s.isRepo, isTrue);
    expect(s.stashCount, 1);
    expect(s.stashes.single.message, 'WIP on main');
  });

  test('status on a non-repo reports isRepo false and no branch', () async {
    when(() => git.isRepo(root)).thenAnswer((_) async => false);

    final s = await service.status(root);

    expect(s.isRepo, isFalse);
    expect(s.current, isNull);
  });

  test('isDirty flushes the pending mirror before asking git', () async {
    // The race: a mirror scheduled moments ago has not landed, so an unflushed
    // `git status` would wrongly report a clean tree.
    sync.scheduleMirror(root, const []);

    await service.isDirty(root);

    verifyInOrder([
      () => ds.write(root, any()),
      () => git.status(root),
    ]);
  });

  test('isDirty is true when git reports any entry', () async {
    when(() => git.status(root)).thenAnswer(
      (_) async => const [
        GitStatusEntry(
          indexStatus: ' ',
          worktreeStatus: 'M',
          path: 'a.req.json',
        ),
      ],
    );

    expect(await service.isDirty(root), isTrue);
  });

  test('switchTo delegates to git', () async {
    await service.switchTo(root, 'feat/x');
    verify(() => git.switchBranch(root, 'feat/x')).called(1);
  });

  test('push sets upstream only when the branch has none', () async {
    when(() => git.hasUpstream(root)).thenAnswer((_) async => false);
    await service.push(root);
    verify(() => git.push(root, setUpstream: true)).called(1);

    when(() => git.hasUpstream(root)).thenAnswer((_) async => true);
    await service.push(root);
    verify(() => git.push(root, setUpstream: false)).called(1);
  });

  test('stash flushes the pending mirror first', () async {
    sync.scheduleMirror(root, const []);

    await service.stash(root, 'wip');

    verifyInOrder([
      () => ds.write(root, any()),
      () => git.stashPush(root, 'wip'),
    ]);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/features/collections/data/services/git_branch_service_test.dart`
Expected: FAIL — `git_branch_service.dart` does not exist.

- [ ] **Step 3: Write the domain entities**

Create `lib/features/collections/domain/entities/branch_status.dart`:

```dart
import 'package:equatable/equatable.dart';

/// One stashed change set. Domain-owned (the domain layer never depends on
/// infrastructure types).
class StashInfo extends Equatable {
  const StashInfo({required this.index, required this.message});
  final int index;
  final String message;

  @override
  List<Object?> get props => [index, message];
}

/// The git state of the workspace, as the branch chip needs it.
class BranchStatus extends Equatable {
  const BranchStatus({
    this.isRepo = false,
    this.current,
    this.branches = const [],
    this.ahead = 0,
    this.behind = 0,
    this.hasRemote = false,
    this.stashes = const [],
  });

  /// Nothing to show: not a repo (or git is unavailable).
  static const none = BranchStatus();

  final bool isRepo;
  final String? current;
  final List<String> branches;
  final int ahead;
  final int behind;
  final bool hasRemote;
  final List<StashInfo> stashes;

  int get stashCount => stashes.length;

  @override
  List<Object?> get props => [
    isRepo,
    current,
    branches,
    ahead,
    behind,
    hasRemote,
    stashes,
  ];
}
```

- [ ] **Step 4: Write the domain abstraction**

Create `lib/features/collections/domain/branch_service.dart`:

```dart
import 'package:getman/features/collections/domain/entities/branch_status.dart';

/// Branch + sync operations over the git workspace. The bloc depends on this
/// abstraction, never on the concrete data-layer implementation.
abstract class BranchService {
  Future<BranchStatus> status(String root);

  /// Whether the workspace has uncommitted changes. Flushes any pending
  /// mirror write first, so the answer reflects what is really on disk.
  Future<bool> isDirty(String root);

  Future<void> switchTo(String root, String branch);
  Future<void> create(String root, String branch);
  Future<void> pull(String root);
  Future<void> push(String root);
  Future<void> stash(String root, String message);
  Future<void> popStash(String root, int index);
  Future<void> dropStash(String root, int index);
}
```

- [ ] **Step 5: Write the implementation**

Create `lib/features/collections/data/services/git_branch_service.dart`:

```dart
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';

/// Composes [GitService] + [WorkspaceSyncService] into the branch/sync
/// operations. Pure of `dart:io` — all git access goes through [GitService].
class GitBranchService implements BranchService {
  GitBranchService(this._git, this._sync);
  final GitService _git;
  final WorkspaceSyncService _sync;

  @override
  Future<BranchStatus> status(String root) async {
    if (!await _git.isAvailable()) return BranchStatus.none;
    if (!await _git.isRepo(root)) return BranchStatus.none;
    final ab = await _git.aheadBehind(root);
    final stashes = await _git.stashList(root);
    return BranchStatus(
      isRepo: true,
      current: await _git.currentBranch(root),
      branches: await _git.branches(root),
      ahead: ab.ahead,
      behind: ab.behind,
      hasRemote: await _git.hasRemote(root),
      stashes: [
        for (final s in stashes) StashInfo(index: s.index, message: s.message),
      ],
    );
  }

  @override
  Future<bool> isDirty(String root) async {
    await _sync.flushPending();
    return (await _git.status(root)).isNotEmpty;
  }

  @override
  Future<void> switchTo(String root, String branch) async {
    await _sync.flushPending();
    await _git.switchBranch(root, branch);
  }

  @override
  Future<void> create(String root, String branch) async {
    await _sync.flushPending();
    await _git.createBranch(root, branch);
  }

  @override
  Future<void> pull(String root) async {
    await _sync.flushPending();
    await _git.pull(root);
  }

  @override
  Future<void> push(String root) async {
    await _sync.flushPending();
    await _git.push(root, setUpstream: !await _git.hasUpstream(root));
  }

  @override
  Future<void> stash(String root, String message) async {
    await _sync.flushPending();
    await _git.stashPush(root, message);
  }

  @override
  Future<void> popStash(String root, int index) async {
    await _sync.flushPending();
    await _git.stashPop(root, index);
  }

  @override
  Future<void> dropStash(String root, int index) => _git.stashDrop(root, index);
}
```

- [ ] **Step 6: Register in DI**

In `lib/core/di/injection_container.dart`, add after the existing
`registerLazySingleton<ReviewService>(...)` line:

```dart
    ..registerLazySingleton<BranchService>(() => GitBranchService(sl(), sl()))
```

with the imports:

```dart
import 'package:getman/features/collections/data/services/git_branch_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `fvm flutter test test/features/collections/data/services/git_branch_service_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 8: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint`
Expected: no issues. In particular `domain_no_infrastructure_imports` must not fire on the new domain files.

```bash
git add lib/features/collections/domain lib/features/collections/data \
        lib/core/di/injection_container.dart \
        test/features/collections/data/services/git_branch_service_test.dart
git commit -m "feat(git): BranchService abstraction + GitBranchService"
```

---

### Task 6: GitSyncBloc

**Files:**
- Create: `lib/features/collections/presentation/bloc/git_sync_event.dart`
- Create: `lib/features/collections/presentation/bloc/git_sync_state.dart`
- Create: `lib/features/collections/presentation/bloc/git_sync_bloc.dart`
- Modify: `lib/core/di/injection_container.dart`
- Test: `test/features/collections/presentation/bloc/git_sync_bloc_test.dart`

**Interfaces:**
- Consumes: `BranchService`, `BranchStatus`, `StashInfo` (Task 5).
- Produces:
  - `GitSyncState` (Equatable): `{GitSyncStatus status, BranchStatus branch, String? errorMessage, int reloadToken}` where `enum GitSyncStatus { initial, loading, ready, busy, error }`.
  - Events: `LoadBranchStatus(root)`, `SwitchBranch(root, branch)`, `CreateBranch(root, branch)`, `PullChanges(root)`, `PushChanges(root)`, `StashChanges(root, message)`, `PopStash(root, index)`, `DropStash(root, index)`.
  - `GitSyncBloc({required BranchService service})`.

`reloadToken` increments **only** after a successful `SwitchBranch`, `PullChanges`, `PopStash`, or `StashChanges` — i.e. every operation that can change the files on disk. Task 7's listener reloads the tree when it changes.

Dirty guard: `SwitchBranch` checks `isDirty` first and, when dirty, emits `error` with the message `'You have uncommitted changes'` **without** touching git. The widget renders the commit/stash choice.

- [ ] **Step 1: Write the failing tests**

Create `test/features/collections/presentation/bloc/git_sync_bloc_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements BranchService {}

void main() {
  const root = '/ws';
  late _MockService service;

  const status = BranchStatus(
    isRepo: true,
    current: 'main',
    branches: ['main', 'feat/x'],
    ahead: 2,
    hasRemote: true,
  );

  setUp(() {
    service = _MockService();
    when(() => service.status(root)).thenAnswer((_) async => status);
    when(() => service.isDirty(root)).thenAnswer((_) async => false);
    when(() => service.switchTo(root, any())).thenAnswer((_) async {});
    when(() => service.create(root, any())).thenAnswer((_) async {});
    when(() => service.pull(root)).thenAnswer((_) async {});
    when(() => service.push(root)).thenAnswer((_) async {});
    when(() => service.stash(root, any())).thenAnswer((_) async {});
  });

  blocTest<GitSyncBloc, GitSyncState>(
    'LoadBranchStatus → ready with the branch status',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const LoadBranchStatus(root)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.branch.current, 'main');
      expect(b.state.branch.ahead, 2);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'SwitchBranch on a clean tree switches and bumps reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const SwitchBranch(root, 'feat/x')),
    verify: (b) {
      verify(() => service.switchTo(root, 'feat/x')).called(1);
      expect(b.state.reloadToken, 1);
      expect(b.state.status, GitSyncStatus.ready);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'SwitchBranch on a dirty tree is refused without touching git',
    build: () {
      when(() => service.isDirty(root)).thenAnswer((_) async => true);
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const SwitchBranch(root, 'feat/x')),
    verify: (b) {
      verifyNever(() => service.switchTo(root, any()));
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('uncommitted changes'));
      expect(b.state.reloadToken, 0); // nothing changed on disk
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PullChanges surfaces the git error and does not bump reloadToken',
    build: () {
      when(() => service.pull(root)).thenThrow(Exception('CONFLICT in a.json'));
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const PullChanges(root)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('CONFLICT'));
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PullChanges success bumps reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const PullChanges(root)),
    verify: (b) => expect(b.state.reloadToken, 1),
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PushChanges does not bump reloadToken (disk is unchanged)',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const PushChanges(root)),
    verify: (b) {
      verify(() => service.push(root)).called(1);
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'StashChanges stashes and bumps reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const StashChanges(root, 'wip')),
    verify: (b) {
      verify(() => service.stash(root, 'wip')).called(1);
      expect(b.state.reloadToken, 1);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'CreateBranch creates and reloads status',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const CreateBranch(root, 'feat/y')),
    verify: (b) {
      verify(() => service.create(root, 'feat/y')).called(1);
      expect(b.state.status, GitSyncStatus.ready);
    },
  );
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/features/collections/presentation/bloc/git_sync_bloc_test.dart`
Expected: FAIL — `git_sync_bloc.dart` does not exist.

- [ ] **Step 3: Write the events**

Create `lib/features/collections/presentation/bloc/git_sync_event.dart`:

```dart
import 'package:equatable/equatable.dart';

abstract class GitSyncEvent extends Equatable {
  const GitSyncEvent();
  @override
  List<Object?> get props => [];
}

class LoadBranchStatus extends GitSyncEvent {
  const LoadBranchStatus(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class SwitchBranch extends GitSyncEvent {
  const SwitchBranch(this.root, this.branch);
  final String root;
  final String branch;
  @override
  List<Object?> get props => [root, branch];
}

class CreateBranch extends GitSyncEvent {
  const CreateBranch(this.root, this.branch);
  final String root;
  final String branch;
  @override
  List<Object?> get props => [root, branch];
}

class PullChanges extends GitSyncEvent {
  const PullChanges(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class PushChanges extends GitSyncEvent {
  const PushChanges(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class StashChanges extends GitSyncEvent {
  const StashChanges(this.root, this.message);
  final String root;
  final String message;
  @override
  List<Object?> get props => [root, message];
}

class PopStash extends GitSyncEvent {
  const PopStash(this.root, this.index);
  final String root;
  final int index;
  @override
  List<Object?> get props => [root, index];
}

class DropStash extends GitSyncEvent {
  const DropStash(this.root, this.index);
  final String root;
  final int index;
  @override
  List<Object?> get props => [root, index];
}
```

- [ ] **Step 4: Write the state**

Create `lib/features/collections/presentation/bloc/git_sync_state.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';

enum GitSyncStatus { initial, loading, ready, busy, error }

class GitSyncState extends Equatable {
  const GitSyncState({
    this.status = GitSyncStatus.initial,
    this.branch = BranchStatus.none,
    this.errorMessage,
    this.reloadToken = 0,
  });

  final GitSyncStatus status;
  final BranchStatus branch;
  final String? errorMessage;

  /// Bumped after any operation that changed the files on disk (switch, pull,
  /// stash, pop). The widget-layer BranchSyncListener reloads the collections
  /// tree when it changes — blocs never talk to each other directly.
  final int reloadToken;

  bool get isBusy => status == GitSyncStatus.busy;

  GitSyncState copyWith({
    GitSyncStatus? status,
    BranchStatus? branch,
    String? errorMessage,
    int? reloadToken,
  }) => GitSyncState(
    status: status ?? this.status,
    branch: branch ?? this.branch,
    // Cleared on every non-error emission: a stale banner outlives its cause.
    errorMessage: status == GitSyncStatus.error ? errorMessage : null,
    reloadToken: reloadToken ?? this.reloadToken,
  );

  @override
  List<Object?> get props => [status, branch, errorMessage, reloadToken];
}
```

- [ ] **Step 5: Write the bloc**

Create `lib/features/collections/presentation/bloc/git_sync_bloc.dart`:

```dart
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';

/// Drives branch + sync over [BranchService]. Errors are surfaced in state
/// (never only logged) — a silent failure here looks like a no-op to the user.
class GitSyncBloc extends Bloc<GitSyncEvent, GitSyncState> {
  GitSyncBloc({required BranchService service})
    : _service = service,
      super(const GitSyncState()) {
    on<LoadBranchStatus>(_onLoad);
    on<SwitchBranch>(_onSwitch);
    on<CreateBranch>(_onCreate);
    on<PullChanges>(_onPull);
    on<PushChanges>(_onPush);
    on<StashChanges>(_onStash);
    on<PopStash>(_onPop);
    on<DropStash>(_onDrop);
  }

  final BranchService _service;

  Future<void> _onLoad(
    LoadBranchStatus event,
    Emitter<GitSyncState> emit,
  ) async {
    emit(state.copyWith(status: GitSyncStatus.loading));
    await _refresh(event.root, emit);
  }

  /// Re-reads git state. [reloadToken] is bumped when the operation changed the
  /// files on disk, so the collections tree gets reloaded.
  Future<void> _refresh(
    String root,
    Emitter<GitSyncState> emit, {
    bool changedDisk = false,
  }) async {
    try {
      final branch = await _service.status(root);
      emit(
        state.copyWith(
          status: GitSyncStatus.ready,
          branch: branch,
          reloadToken: changedDisk ? state.reloadToken + 1 : state.reloadToken,
        ),
      );
    } on Object catch (e) {
      _fail(e, emit, 'status');
    }
  }

  void _fail(Object e, Emitter<GitSyncState> emit, String op) {
    log('$op failed: $e', name: 'GitSyncBloc');
    emit(
      state.copyWith(
        status: GitSyncStatus.error,
        errorMessage: e.toString(),
      ),
    );
  }

  /// Runs [action], then refreshes. Returns false when it failed.
  Future<bool> _run(
    String root,
    Emitter<GitSyncState> emit,
    String op,
    Future<void> Function() action, {
    bool changedDisk = false,
  }) async {
    emit(state.copyWith(status: GitSyncStatus.busy));
    try {
      await action();
    } on Object catch (e) {
      _fail(e, emit, op);
      return false;
    }
    await _refresh(root, emit, changedDisk: changedDisk);
    return true;
  }

  Future<void> _onSwitch(SwitchBranch event, Emitter<GitSyncState> emit) async {
    emit(state.copyWith(status: GitSyncStatus.busy));
    final bool dirty;
    try {
      dirty = await _service.isDirty(event.root);
    } on Object catch (e) {
      _fail(e, emit, 'switch');
      return;
    }
    if (dirty) {
      // Refuse rather than clobber. The widget offers commit or stash.
      emit(
        state.copyWith(
          status: GitSyncStatus.error,
          errorMessage: 'You have uncommitted changes',
        ),
      );
      return;
    }
    await _run(
      event.root,
      emit,
      'switch',
      () => _service.switchTo(event.root, event.branch),
      changedDisk: true,
    );
  }

  Future<void> _onCreate(CreateBranch event, Emitter<GitSyncState> emit) =>
      _run(
        event.root,
        emit,
        'create',
        () => _service.create(event.root, event.branch),
      );

  Future<void> _onPull(PullChanges event, Emitter<GitSyncState> emit) => _run(
    event.root,
    emit,
    'pull',
    () => _service.pull(event.root),
    changedDisk: true,
  );

  Future<void> _onPush(PushChanges event, Emitter<GitSyncState> emit) =>
      _run(event.root, emit, 'push', () => _service.push(event.root));

  Future<void> _onStash(StashChanges event, Emitter<GitSyncState> emit) => _run(
    event.root,
    emit,
    'stash',
    () => _service.stash(event.root, event.message),
    changedDisk: true,
  );

  Future<void> _onPop(PopStash event, Emitter<GitSyncState> emit) => _run(
    event.root,
    emit,
    'pop stash',
    () => _service.popStash(event.root, event.index),
    changedDisk: true,
  );

  Future<void> _onDrop(DropStash event, Emitter<GitSyncState> emit) => _run(
    event.root,
    emit,
    'drop stash',
    () => _service.dropStash(event.root, event.index),
  );
}
```

- [ ] **Step 6: Register in DI**

In `lib/core/di/injection_container.dart`, after the `ReviewBloc` registration:

```dart
    ..registerFactory(() => GitSyncBloc(service: sl()))
```

with the import:

```dart
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `fvm flutter test test/features/collections/presentation/bloc/git_sync_bloc_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 8: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib`
Expected: no issues from any pass. `bloc_depends_on_abstractions` must not fire — the bloc imports only `domain/`.

```bash
git add lib/features/collections/presentation/bloc lib/core/di/injection_container.dart \
        test/features/collections/presentation/bloc/git_sync_bloc_test.dart
git commit -m "feat(git): GitSyncBloc over the BranchService abstraction"
```

---

### Task 7: BranchSyncListener — reload the tree after git changes disk

**Files:**
- Create: `lib/features/collections/presentation/widgets/branch_sync_listener.dart`
- Modify: `lib/main.dart`
- Test: `test/features/collections/presentation/widgets/branch_sync_listener_test.dart`

**Interfaces:**
- Consumes: `GitSyncBloc`/`GitSyncState.reloadToken` (Task 6), `WorkspaceSyncService.read(root)`, `CollectionsBloc` + `ReplaceCollections(List<CollectionNodeEntity>)`, `SettingsBloc` → `state.settings.workspacePath`.
- Produces: `BranchSyncListener({required Widget child})` — mounted above `MaterialApp` alongside the existing `WorkspaceSyncListener`.

This is the coordinator that keeps blocs decoupled: `GitSyncBloc` never imports `CollectionsBloc`.

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/presentation/widgets/branch_sync_listener_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/branch_sync_listener.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

class _MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

class _MockDataSource extends Mock implements WorkspaceCollectionsDataSource {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

void main() {
  const root = '/ws';
  const node = CollectionNodeEntity(
    id: 'n',
    name: 'From disk',
    isFolder: false,
    config: HttpRequestConfigEntity(id: 'n'),
  );

  late _MockGitSyncBloc gitSync;
  late _MockCollectionsBloc collections;
  late _MockSettingsBloc settings;
  late _MockDataSource ds;

  setUpAll(() => registerFallbackValue(_FakeCollectionsEvent()));

  setUp(() {
    gitSync = _MockGitSyncBloc();
    collections = _MockCollectionsBloc();
    settings = _MockSettingsBloc();
    ds = _MockDataSource();
    when(() => ds.read(root)).thenAnswer((_) async => const [node]);
    when(() => collections.state).thenReturn(const CollectionsState());
    when(() => settings.state).thenReturn(
      const SettingsState(settings: SettingsEntity(workspacePath: root)),
    );
    when(() => settings.stream).thenAnswer((_) => const Stream.empty());
  });

  testWidgets('a bumped reloadToken reloads the tree from disk', (
    tester,
  ) async {
    whenListen(
      gitSync,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(status: GitSyncStatus.ready),
        const GitSyncState(status: GitSyncStatus.ready, reloadToken: 1),
      ]),
      initialState: const GitSyncState(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<WorkspaceSyncService>(
          create: (_) => WorkspaceSyncService(ds),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<GitSyncBloc>.value(value: gitSync),
              BlocProvider<CollectionsBloc>.value(value: collections),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: const BranchSyncListener(child: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final captured = verify(
      () => collections.add(captureAny()),
    ).captured.whereType<ReplaceCollections>().toList();
    expect(captured, hasLength(1));
    expect(captured.single.collections.single.name, 'From disk');
  });

  testWidgets('an unchanged reloadToken does not reload', (tester) async {
    whenListen(
      gitSync,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(status: GitSyncStatus.busy),
        const GitSyncState(status: GitSyncStatus.ready),
      ]),
      initialState: const GitSyncState(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<WorkspaceSyncService>(
          create: (_) => WorkspaceSyncService(ds),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<GitSyncBloc>.value(value: gitSync),
              BlocProvider<CollectionsBloc>.value(value: collections),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: const BranchSyncListener(child: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    verifyNever(() => ds.read(any()));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/branch_sync_listener_test.dart`
Expected: FAIL — `branch_sync_listener.dart` does not exist.

- [ ] **Step 3: Write the listener**

Create `lib/features/collections/presentation/widgets/branch_sync_listener.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';

/// Reloads the collections tree from disk after a git operation changed the
/// files under the app (branch switch, pull, stash, pop).
///
/// This is a widget-layer coordinator by design: GitSyncBloc must not depend on
/// CollectionsBloc (no bloc→bloc coupling), so the widget that holds both does
/// the wiring — same shape as [WorkspaceSyncListener].
class BranchSyncListener extends StatelessWidget {
  const BranchSyncListener({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<GitSyncBloc, GitSyncState>(
      listenWhen: (prev, next) => prev.reloadToken != next.reloadToken,
      listener: (context, state) async {
        final path = context.read<SettingsBloc>().state.settings.workspacePath;
        if (path == null || path.isEmpty) return;
        final sync = context.read<WorkspaceSyncService>();
        final collections = context.read<CollectionsBloc>();
        List<CollectionNodeEntity> onDisk;
        try {
          onDisk = await sync.read(path);
        } on Object catch (_) {
          return; // best-effort: a failed read must not break the session
        }
        collections.add(ReplaceCollections(onDisk));
      },
      child: child,
    );
  }
}
```

- [ ] **Step 4: Mount it in main.dart**

In `lib/main.dart`, provide the bloc and wrap the tree. Add to the
`MultiBlocProvider` providers list, after the `ReviewBloc` provider:

```dart
          BlocProvider(create: (_) => di.sl<GitSyncBloc>()),
```

and wrap the existing `WorkspaceSyncListener` so both listeners are active:

```dart
        child: NetworkSettingsListener(
          child: WorkspaceSyncListener(
            child: BranchSyncListener(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                // ... existing body unchanged
              ),
            ),
          ),
        ),
```

with the imports:

```dart
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/widgets/branch_sync_listener.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `fvm flutter test test/features/collections/presentation/widgets/branch_sync_listener_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint && fvm flutter test`
Expected: everything green (main.dart is widely depended on — run the full suite here).

```bash
git add lib/features/collections/presentation/widgets/branch_sync_listener.dart \
        lib/main.dart \
        test/features/collections/presentation/widgets/branch_sync_listener_test.dart
git commit -m "feat(git): reload collections from disk after branch switch/pull"
```

---

### Task 8: BranchChip — the header chip + menu + dirty prompt

**Files:**
- Create: `lib/features/collections/presentation/widgets/branch_chip.dart`
- Modify: `lib/features/collections/presentation/widgets/collections_list.dart`
- Test: `test/features/collections/presentation/widgets/branch_chip_test.dart`

**Interfaces:**
- Consumes: `GitSyncBloc`, `GitSyncState`, `BranchStatus` (Tasks 5–6); `SettingsBloc` → `workspacePath`; `ReviewChangesDialog.show(context, root: root)`; `NamePromptDialog.show(context, title:, onConfirm:, ...)`; `StashListDialog.show(context, root: root)` (Task 9 — **create Task 9's file first if it does not exist**, or land Task 9 before this task's menu wires it).
- Produces: `BranchChip()` — a `StatelessWidget` mounted in the collections header.

Mirror `ReviewChangesButton`: hidden on web, and hidden when `workspacePath == null` (the Review button already routes an unconfigured user to the WORKSPACE settings pane, so the chip does not need to duplicate that). Also hidden when `state.branch.isRepo` is false — the Review dialog owns `git init`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/collections/presentation/widgets/branch_chip_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/branch_chip.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  const root = '/ws';
  late _MockGitSyncBloc bloc;
  late _MockSettingsBloc settings;

  setUp(() {
    bloc = _MockGitSyncBloc();
    settings = _MockSettingsBloc();
    when(() => settings.state).thenReturn(
      const SettingsState(settings: SettingsEntity(workspacePath: root)),
    );
    when(() => settings.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget host(GitSyncState state) {
    when(() => bloc.state).thenReturn(state);
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<GitSyncBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: const BranchChip(),
        ),
      ),
    );
  }

  testWidgets('shows the branch name and ahead/behind counts', (tester) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
            ahead: 2,
            behind: 3,
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('main'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is hidden when the workspace is not a git repo', (tester) async {
    await tester.pumpWidget(
      host(const GitSyncState(status: GitSyncStatus.ready)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('branch_chip')), findsNothing);
  });

  testWidgets('the menu switches branch on tap', (tester) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main', 'feat/x'],
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feat/x').last);
    await tester.pumpAndSettle();

    verify(() => bloc.add(const SwitchBranch(root, 'feat/x'))).called(1);
  });

  testWidgets('Pull dispatches PullChanges', (tester) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main'],
            hasRemote: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('branch_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('branch_menu_pull')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const PullChanges(root))).called(1);
  });

  testWidgets('a dirty-switch error shows the commit/stash prompt', (
    tester,
  ) async {
    whenListen(
      bloc,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(
          status: GitSyncStatus.error,
          errorMessage: 'You have uncommitted changes',
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main', 'feat/x'],
          ),
        ),
      ]),
      initialState: const GitSyncState(
        status: GitSyncStatus.ready,
        branch: BranchStatus(
          isRepo: true,
          current: 'main',
          branches: ['main', 'feat/x'],
        ),
      ),
    );

    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(
            isRepo: true,
            current: 'main',
            branches: ['main', 'feat/x'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REVIEW CHANGES…'), findsOneWidget);
    expect(find.text('STASH CHANGES'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/features/collections/presentation/widgets/branch_chip_test.dart`
Expected: FAIL — `branch_chip.dart` does not exist.

- [ ] **Step 3: Write the chip**

Create `lib/features/collections/presentation/widgets/branch_chip.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/stash_list_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Collections-header chip: current branch + ahead/behind, opening the branch
/// and sync menu. Hidden on web, without a workspace, or when the workspace is
/// not a git repo (the Review dialog owns `git init`).
class BranchChip extends StatelessWidget {
  const BranchChip({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.workspacePath != n.settings.workspacePath,
      builder: (context, settingsState) {
        final root = settingsState.settings.workspacePath;
        if (root == null || root.isEmpty) return const SizedBox.shrink();

        return BlocConsumer<GitSyncBloc, GitSyncState>(
          listenWhen: (p, n) =>
              p.errorMessage != n.errorMessage && n.errorMessage != null,
          listener: (context, state) {
            final message = state.errorMessage;
            if (message == null) return;
            if (message.contains('uncommitted changes')) {
              _promptDirty(context, root);
            } else {
              _showError(context, message);
            }
          },
          builder: (context, state) {
            final branch = state.branch;
            if (!branch.isRepo || branch.current == null) {
              return const SizedBox.shrink();
            }
            return _chip(context, root, state);
          },
        );
      },
    );
  }

  Widget _chip(BuildContext context, String root, GitSyncState state) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final branch = state.branch;
    final bloc = context.read<GitSyncBloc>();

    return PopupMenuButton<String>(
      key: const ValueKey('branch_chip'),
      tooltip: 'Branch & sync',
      enabled: !state.isBusy,
      onSelected: (value) => _onSelected(context, root, value),
      itemBuilder: (context) => [
        for (final b in branch.branches)
          PopupMenuItem<String>(
            value: 'switch:$b',
            child: Row(
              children: [
                Icon(
                  b == branch.current ? Icons.check : null,
                  size: layout.smallIconSize,
                ),
                SizedBox(width: layout.tabSpacing),
                Text(b),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'new',
          child: const Text('NEW BRANCH…'),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('branch_menu_pull'),
          value: 'pull',
          enabled: branch.hasRemote,
          child: Text(
            branch.hasRemote ? 'PULL (REBASE)' : 'PULL — NO REMOTE',
          ),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('branch_menu_push'),
          value: 'push',
          enabled: branch.hasRemote,
          child: Text(branch.hasRemote ? 'PUSH' : 'PUSH — NO REMOTE'),
        ),
        PopupMenuItem<String>(
          value: 'stashes',
          child: Text('STASHES (${branch.stashCount})'),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.tabSpacing),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: layout.smallIconSize),
            SizedBox(width: layout.tabSpacing),
            Flexible(
              child: Text(
                branch.current!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  fontWeight: context.appTypography.titleWeight,
                ),
              ),
            ),
            if (branch.ahead > 0)
              Text(
                ' ↑${branch.ahead}',
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (branch.behind > 0)
              Text(
                ' ↓${branch.behind}',
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onSelected(BuildContext context, String root, String value) {
    final bloc = context.read<GitSyncBloc>();
    if (value.startsWith('switch:')) {
      bloc.add(SwitchBranch(root, value.substring('switch:'.length)));
      return;
    }
    switch (value) {
      case 'new':
        NamePromptDialog.show(
          context,
          title: 'NEW BRANCH',
          hintText: 'feat/my-change',
          confirmLabel: 'CREATE',
          onConfirm: (name) => bloc.add(CreateBranch(root, name)),
        );
      case 'pull':
        bloc.add(PullChanges(root));
      case 'push':
        bloc.add(PushChanges(root));
      case 'stashes':
        StashListDialog.show(context, root: root);
    }
  }

  /// A switch was refused because the tree is dirty: offer the two ways out.
  void _promptDirty(BuildContext context, String root) {
    final bloc = context.read<GitSyncBloc>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('UNCOMMITTED CHANGES'),
        content: const Text(
          'Commit or stash your changes before switching branches.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ReviewChangesDialog.show(context, root: root);
            },
            child: const Text('REVIEW CHANGES…'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              bloc.add(StashChanges(root, 'Getman WIP'));
            },
            child: const Text('STASH CHANGES'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('branch_error_dialog'),
        title: const Text('GIT ERROR'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}
```

Note: remove the unused `bloc` local in `_chip` if the analyzer flags it — the
menu callbacks read the bloc from `context` in `_onSelected`.

- [ ] **Step 4: Mount it in the collections header**

In `lib/features/collections/presentation/widgets/collections_list.dart`, in the
header `Row` that currently ends with `const ReviewChangesButton(),` (around
line 385), insert **before** the review button:

```dart
                const BranchChip(),
                SizedBox(width: layout.tabSpacing),
```

with the import:

```dart
import 'package:getman/features/collections/presentation/widgets/branch_chip.dart';
```

Also dispatch the initial status load: the chip is rendered inside the
collections panel, so add to the same file's `initState` (or, if it is a
`StatelessWidget`, in `BranchChip` itself via a `StatefulWidget` post-frame
callback like `ReviewChangesButton` does) a `LoadBranchStatus(root)` when a
workspace path exists, and refresh it on `WorkspaceSyncService.mirrored` —
reusing exactly the pattern in
`lib/features/collections/presentation/widgets/review_changes_button.dart`
(subscribe in `initState`, dispatch in a post-frame callback, cancel in
`dispose`). Convert `BranchChip` to a `StatefulWidget` for this.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `fvm flutter test test/features/collections/presentation/widgets/branch_chip_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Run the collections suite (the header changed)**

Run: `fvm flutter test test/features/collections test/features/home`
Expected: PASS. The `collections_list` / `side_menu` widget tests now need a
`GitSyncBloc` provider (they already provide `ReviewBloc` +
`WorkspaceSyncService`); add a `MockGitSyncBloc` to those hosts exactly as
`ReviewBloc` was added.

- [ ] **Step 7: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint`

```bash
git add lib/features/collections/presentation/widgets \
        test/features/collections test/features/home
git commit -m "feat(git): branch chip with ahead/behind + branch & sync menu"
```

---

### Task 9: StashListDialog

**Files:**
- Create: `lib/features/collections/presentation/widgets/stash_list_dialog.dart`
- Test: `test/features/collections/presentation/widgets/stash_list_dialog_test.dart`

**Interfaces:**
- Consumes: `GitSyncBloc`, `GitSyncState`, `StashInfo`, events `PopStash(root, index)` / `DropStash(root, index)`; `showResponsiveDialog<void>(context, builder:)` and `ResponsiveDialogScaffold` (see `review_changes_dialog.dart` for the exact usage); `ConfirmDialog.show(...)`.
- Produces: `StashListDialog.show(BuildContext context, {required String root})`.

**Build this before Task 8** (Task 8's menu imports it), or land both in either order and fix the import — but the file must exist for Task 8 to compile.

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/presentation/widgets/stash_list_dialog_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/stash_list_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

void main() {
  const root = '/ws';
  late _MockGitSyncBloc bloc;

  setUp(() => bloc = _MockGitSyncBloc());

  Widget host(GitSyncState state) {
    when(() => bloc.state).thenReturn(state);
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: BlocProvider<GitSyncBloc>.value(
        value: bloc,
        child: const Scaffold(body: StashListBody(root: root)),
      ),
    );
  }

  const withStashes = GitSyncState(
    status: GitSyncStatus.ready,
    branch: BranchStatus(
      isRepo: true,
      current: 'main',
      stashes: [StashInfo(index: 0, message: 'WIP on main: getman')],
    ),
  );

  testWidgets('lists stashes', (tester) async {
    await tester.pumpWidget(host(withStashes));
    await tester.pumpAndSettle();

    expect(find.textContaining('WIP on main'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('POP dispatches PopStash', (tester) async {
    await tester.pumpWidget(host(withStashes));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stash_pop_0')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const PopStash(root, 0))).called(1);
  });

  testWidgets('empty state tells the user there is nothing stashed', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const GitSyncState(
          status: GitSyncStatus.ready,
          branch: BranchStatus(isRepo: true, current: 'main'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No stashes.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/stash_list_dialog_test.dart`
Expected: FAIL — `stash_list_dialog.dart` does not exist.

- [ ] **Step 3: Write the dialog**

Create `lib/features/collections/presentation/widgets/stash_list_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';

/// Lists `git stash` entries with pop/drop. Without this, a stash Getman
/// creates would be invisible work the user cannot get back to.
class StashListDialog {
  const StashListDialog._();

  static Future<void> show(BuildContext context, {required String root}) {
    final bloc = context.read<GitSyncBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => BlocProvider<GitSyncBloc>.value(
        value: bloc,
        child: StashListBody(root: root),
      ),
    );
  }
}

/// The dialog content (public for widget testing).
class StashListBody extends StatelessWidget {
  const StashListBody({required this.root, super.key});
  final String root;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocBuilder<GitSyncBloc, GitSyncState>(
      builder: (context, state) {
        final stashes = state.branch.stashes;
        return ResponsiveDialogScaffold(
          title: const Text('STASHES'),
          content: SizedBox(
            width: layout.dialogWidth,
            height: layout.settingsDialogHeight,
            child: stashes.isEmpty
                ? const Center(child: Text('No stashes.'))
                : ListView.builder(
                    itemCount: stashes.length,
                    itemBuilder: (context, i) {
                      final s = stashes[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          s.message,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              key: ValueKey('stash_pop_${s.index}'),
                              onPressed: () => context.read<GitSyncBloc>().add(
                                PopStash(root, s.index),
                              ),
                              child: const Text('POP'),
                            ),
                            TextButton(
                              key: ValueKey('stash_drop_${s.index}'),
                              onPressed: () => ConfirmDialog.show(
                                context,
                                title: 'DROP STASH',
                                message:
                                    'This discards the stashed changes for '
                                    'good.',
                                confirmLabel: 'DROP',
                                onConfirm: () => context
                                    .read<GitSyncBloc>()
                                    .add(DropStash(root, s.index)),
                              ),
                              child: const Text('DROP'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }
}
```

Check `ConfirmDialog.show`'s real signature in
`lib/core/ui/widgets/confirm_dialog.dart` and match it exactly (it may return a
`Future` — if so, wrap the call in `unawaited(...)` to satisfy
`discarded_futures`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/features/collections/presentation/widgets/stash_list_dialog_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify + commit**

Run: `fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint`

```bash
git add lib/features/collections/presentation/widgets/stash_list_dialog.dart \
        test/features/collections/presentation/widgets/stash_list_dialog_test.dart
git commit -m "feat(git): stash list dialog (pop/drop)"
```

---

### Task 10: Full gate + wiki

**Files:**
- Modify: `docs/superpowers/plans/2026-07-13-git-branch-sync.md` (tick the boxes)
- External: the `Getman.wiki.git` repo — **Version Control** page

- [ ] **Step 1: Run the complete verification bar**

```bash
fvm dart format lib test tools
fvm flutter analyze
fvm dart run custom_lint
( cd tools/getman_lints/example && fvm dart run custom_lint )
fvm dart run bloc_tools:bloc lint lib < /dev/null
fvm flutter test
```

Expected: **0 issues from every analysis pass and 100% green tests.** These are
separate processes — a clean `flutter analyze` does not imply custom_lint or
bloc_lint are clean.

- [ ] **Step 2: Update the wiki**

The **Version Control** page is owed from Spec A (deferred to its merge). Clone
`https://github.com/thiagomiranda3/Getman.wiki.git`, and write/extend the page
to cover, with **verbatim UI labels**:

- Connect a workspace folder (Settings → WORKSPACE → CHOOSE FOLDER).
- Review changes: the badged button, SELECT ALL, semantic diff, COMMIT.
- **Branch & sync (new):** the branch chip (`main ↑2 ↓3`), switching branches,
  NEW BRANCH…, PULL (REBASE), PUSH, STASHES.
- **Credentials:** "Getman uses your existing git credentials (SSH agent or
  credential helper). Nothing is stored in the app."
- **Conflicts:** a conflicting pull is aborted and left for your git tool —
  in-app conflict resolution is not shipped yet.
- Desktop-only; requires `git` on your PATH.

Commit and push (default branch `master`).

- [ ] **Step 3: Commit the ticked plan**

```bash
git add docs/superpowers/plans/2026-07-13-git-branch-sync.md
git commit -m "docs(git): tick off the Spec B implementation plan"
```

---

## Self-Review Notes

- **Spec coverage:** credentials (no storage → Task 2 uses the system git, wiki
  in Task 10) · dirty switch blocked with commit/stash prompt (Tasks 6, 8) ·
  pull rebase + abort (Task 2) · push upstream (Tasks 2, 5) · branch chip with
  ahead/behind (Task 8) · create branch (Tasks 1, 8) · stash + list (Tasks 3, 9)
  · pending-mirror race (Task 4, guarded in Task 5) · reload without bloc→bloc
  coupling (Task 7) · web-gating (stub methods in Tasks 1–3; `kIsWeb` in Task 8).
- **Ordering caveat:** Task 8 imports Task 9's `StashListDialog`. Implement
  Task 9 **before** Task 8, or Task 8 will not compile.
- **Naming is consistent across tasks:** `AheadBehind{ahead,behind}`,
  `StashEntry{index,message}` (core/git) → `StashInfo{index,message}` (domain),
  `BranchStatus`, `BranchService`, `GitBranchService`, `GitSyncBloc`,
  `reloadToken`.

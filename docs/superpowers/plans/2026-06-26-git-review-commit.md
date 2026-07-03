# Git Review & Commit (Spec A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the workspace directory into a git repo Getman drives, and add a **Review changes** dialog that shows a semantic, request-level diff of working changes, lets the user stage individual requests/folders, and commit — all in-app, desktop-only.

**Architecture:** A web-gated `GitService` shells out to the system `git` CLI (the single `dart:io` boundary; git's own index is the staging source of truth). A pure `SemanticDiff` engine diffs parsed request/folder JSON. A pure `WorkspaceReviewService` composes them into review entries. A `ReviewBloc` (bloc-over-service) drives a `ReviewChangesDialog`.

**Tech Stack:** Flutter, `flutter_bloc`, `equatable`, `dart:io` `Process` (native only), existing `WorkspaceCollectionSerializer` + `LineDiff`, `mocktail` + `bloc_test`. Invoke Flutter as `fvm flutter ...`.

## Global Constraints

- Flutter is pinned via `.fvmrc` — always `fvm flutter ...`, never plain `flutter`.
- Imports are `package:getman/...` everywhere (no relative imports; `directives_ordering` + `always_use_package_imports`; alphabetical within the package group).
- Domain layer is pure Dart + `equatable` — zero imports from `data/`, Flutter, or `dart:io`.
- **`dart:io` may be imported ONLY in `git_service_io.dart`** (web-safety). Web gets the stub via conditional export `export 'git_service_stub.dart' if (dart.library.io) 'git_service_io.dart';`. This mirrors the auto-updater gate.
- BLoCs must not import `package:flutter/foundation.dart`/material (bloc_lint `avoid_flutter_imports`); log via `dart:developer` `log(msg, name: 'ReviewBloc')`, never `debugPrint`/`print`.
- Widgets never call `sl<T>()`/`GetIt` (custom_lint `avoid_get_it_in_widgets`); reach blocs via `BlocProvider`/`context.read`. GetIt only in `lib/core/di/` + `main.dart`.
- No hardcoded sizes/colors/radii/weights in widgets — read from `context.appLayout/appPalette/appTypography/appShape/appDecoration`. No `Colors.black/white/red` literals outside `lib/core/theme/` (custom_lint `avoid_hardcoded_brand_colors`).
- All states/events/entities are `Equatable`; entities immutable.
- **Diff only the fields the workspace serializer actually writes** (see `_configToJson`): `method`, `url`, `headers`, `body`, `bodyType`, `graphqlVariables`, `auth`, `formFields`, `bodyFilePath`. It does NOT persist `kind` or the response cache, so those are never diffed. Auth values are treated as secret — reported as changed without printing values.
- **Verification bar (all clean before "done"):** `fvm flutter analyze` (0), `fvm dart run custom_lint` (0), `fvm dart run bloc_tools:bloc lint lib` (0), `fvm dart format lib test tools` clean, `fvm flutter test` 100% green.
- Scope: **init / status / diff / stage / unstage / commit only.** No push, pull, branch-switch, checkout, merge (later specs). Collections only. Desktop only.

## File Structure

**Create:**
- `lib/core/git/git_service.dart` — abstract `GitService`, `GitStatusEntry`, `GitException`, `createGitService()` (conditional export).
- `lib/core/git/git_service_io.dart` — `_IoGitService` (the only `dart:io` importer) + `createGitService()`.
- `lib/core/git/git_service_stub.dart` — `_StubGitService` (web) + `createGitService()`.
- `lib/features/collections/domain/logic/semantic_diff.dart` — `SemanticDiff`, `FieldChange`, `ChangeKind`, `RequestConfigDiff`, `FolderNodeDiff`.
- `lib/features/collections/domain/entities/review_entry.dart` — `ReviewEntry`, `NodeKind`, `ChangeType`, `ReviewResult`.
- `lib/features/collections/data/services/workspace_review_service.dart` — pure `WorkspaceReviewService` (depends on `GitService`).
- `lib/features/collections/presentation/bloc/review_bloc.dart` / `review_event.dart` / `review_state.dart`.
- `lib/features/collections/presentation/widgets/semantic_diff_view.dart` — renders a `SemanticDiff`.
- `lib/features/collections/presentation/widgets/review_changes_dialog.dart`.
- `lib/features/collections/presentation/widgets/review_changes_button.dart` — badged trigger.
- Tests mirroring each.

**Modify:**
- `lib/core/di/injection_container.dart` — register `GitService`, `WorkspaceReviewService`, `ReviewBloc`.
- `lib/main.dart` — provide `ReviewBloc`.
- `lib/features/collections/presentation/widgets/collections_list.dart` — mount `ReviewChangesButton` in the collections header.

---

### Task 1: Semantic diff engine (pure domain)

**Files:**
- Create: `lib/features/collections/domain/logic/semantic_diff.dart`
- Test: `test/features/collections/domain/logic/semantic_diff_test.dart`

**Interfaces:**
- Produces:
  - `enum ChangeKind { added, removed, changed }`
  - `class FieldChange { final String field; final ChangeKind kind; final String? before; final String? after; }`
  - `class SemanticDiff { final List<FieldChange> changes; bool get isEmpty; }`
  - `class RequestConfigDiff { static SemanticDiff diff(HttpRequestConfigEntity? before, HttpRequestConfigEntity? after); }`
  - `class FolderNodeDiff { static SemanticDiff diff(CollectionNodeEntity? before, CollectionNodeEntity? after); }`

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/domain/logic/semantic_diff_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

void main() {
  HttpRequestConfigEntity cfg({
    String method = 'GET',
    String url = 'https://api.dev',
    Map<String, String> headers = const {},
    String body = '',
    Map<String, String> auth = const {},
  }) => HttpRequestConfigEntity(
    id: 'c',
    method: method,
    url: url,
    headers: headers,
    body: body,
    auth: auth,
  );

  group('RequestConfigDiff', () {
    test('added request reports every non-empty field as added', () {
      final d = RequestConfigDiff.diff(null, cfg(method: 'POST'));
      expect(d.changes.any((c) => c.field == 'method' && c.kind == ChangeKind.added), isTrue);
    });

    test('method + url changes are reported as changed with before/after', () {
      final d = RequestConfigDiff.diff(
        cfg(),
        cfg(method: 'POST', url: 'https://api.dev/v2'),
      );
      final method = d.changes.firstWhere((c) => c.field == 'method');
      expect(method.kind, ChangeKind.changed);
      expect(method.before, 'GET');
      expect(method.after, 'POST');
      expect(d.changes.any((c) => c.field == 'url'), isTrue);
    });

    test('header add/remove/change reported per key', () {
      final d = RequestConfigDiff.diff(
        cfg(headers: {'A': '1', 'B': '2'}),
        cfg(headers: {'A': '9', 'C': '3'}),
      );
      final labels = d.changes.map((c) => '${c.field}:${c.kind.name}').toSet();
      expect(labels, containsAll(<String>{
        "header 'A':changed",
        "header 'B':removed",
        "header 'C':added",
      }));
    });

    test('auth change is reported without leaking values', () {
      final d = RequestConfigDiff.diff(
        cfg(auth: {'type': 'bearer', 'token': 'secret1'}),
        cfg(auth: {'type': 'bearer', 'token': 'secret2'}),
      );
      final auth = d.changes.firstWhere((c) => c.field == 'authentication');
      expect(auth.kind, ChangeKind.changed);
      expect(auth.before, isNull);
      expect(auth.after, isNull);
    });

    test('identical configs produce an empty diff', () {
      expect(RequestConfigDiff.diff(cfg(), cfg()).isEmpty, isTrue);
    });
  });

  group('FolderNodeDiff', () {
    CollectionNodeEntity folder({
      String name = 'F',
      Map<String, String> variables = const {},
      List<CollectionNodeEntity> children = const [],
    }) => CollectionNodeEntity(
      id: 'f',
      name: name,
      isFolder: true,
      children: children,
      variables: variables,
    );

    test('name change reported', () {
      final d = FolderNodeDiff.diff(folder(), folder(name: 'G'));
      final n = d.changes.firstWhere((c) => c.field == 'name');
      expect(n.before, 'F');
      expect(n.after, 'G');
    });

    test('variable add reported per key', () {
      final d = FolderNodeDiff.diff(folder(), folder(variables: {'x': '1'}));
      expect(d.changes.any((c) => c.field == "variable 'x'" && c.kind == ChangeKind.added), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/collections/domain/logic/semantic_diff_test.dart`
Expected: FAIL — `semantic_diff.dart` does not exist.

- [ ] **Step 3: Implement the diff engine**

Create `lib/features/collections/domain/logic/semantic_diff.dart`:

```dart
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

enum ChangeKind { added, removed, changed }

/// One field-level change in a semantic node diff. [before]/[after] are shown
/// verbatim in the diff view; leave both null for masked/opaque changes (auth).
class FieldChange extends Equatable {
  const FieldChange({
    required this.field,
    required this.kind,
    this.before,
    this.after,
  });
  final String field;
  final ChangeKind kind;
  final String? before;
  final String? after;

  @override
  List<Object?> get props => [field, kind, before, after];
}

/// An ordered list of field changes between two versions of a node.
class SemanticDiff extends Equatable {
  const SemanticDiff(this.changes);
  final List<FieldChange> changes;
  bool get isEmpty => changes.isEmpty;

  @override
  List<Object?> get props => [changes];
}

const _mapEq = MapEquality<String, String>();
const _listEq = ListEquality<Object?>();

ChangeKind _kind(Object? before, Object? after) => before == null
    ? ChangeKind.added
    : after == null
    ? ChangeKind.removed
    : ChangeKind.changed;

void _scalar(
  List<FieldChange> out,
  String field,
  String? before,
  String? after,
) {
  final b = (before?.isEmpty ?? true) ? null : before;
  final a = (after?.isEmpty ?? true) ? null : after;
  if (b == a) return;
  out.add(FieldChange(field: field, kind: _kind(b, a), before: b, after: a));
}

void _mapPerKey(
  List<FieldChange> out,
  String label,
  Map<String, String> before,
  Map<String, String> after,
) {
  for (final key in {...before.keys, ...after.keys}) {
    final b = before[key];
    final a = after[key];
    if (b == a) continue;
    out.add(
      FieldChange(
        field: "$label '$key'",
        kind: _kind(b, a),
        before: b,
        after: a,
      ),
    );
  }
}

/// Diffs the workspace-serialized fields of a request config (see
/// WorkspaceCollectionSerializer._configToJson). `kind` and response fields are
/// not persisted, so they are never diffed. Auth is reported as changed without
/// its (secret) values.
class RequestConfigDiff {
  const RequestConfigDiff._();

  static SemanticDiff diff(
    HttpRequestConfigEntity? before,
    HttpRequestConfigEntity? after,
  ) {
    final out = <FieldChange>[];
    _scalar(out, 'method', before?.method, after?.method);
    _scalar(out, 'url', before?.url, after?.url);
    _scalar(out, 'body type', before?.bodyType.name, after?.bodyType.name);
    _scalar(out, 'body', before?.body, after?.body);
    _scalar(
      out,
      'GraphQL variables',
      before?.graphqlVariables,
      after?.graphqlVariables,
    );
    _scalar(out, 'binary file', before?.bodyFilePath, after?.bodyFilePath);
    _mapPerKey(
      out,
      'header',
      before?.headers ?? const {},
      after?.headers ?? const {},
    );

    final beforeAuth = before?.auth ?? const {};
    final afterAuth = after?.auth ?? const {};
    if (!_mapEq.equals(beforeAuth, afterAuth)) {
      out.add(
        FieldChange(
          field: 'authentication',
          kind: _kind(
            beforeAuth.isEmpty ? null : beforeAuth,
            afterAuth.isEmpty ? null : afterAuth,
          ),
        ),
      );
    }

    final beforeForm = before?.formFields ?? const [];
    final afterForm = after?.formFields ?? const [];
    if (!_listEq.equals(beforeForm, afterForm)) {
      out.add(
        FieldChange(
          field: 'form fields',
          kind: _kind(
            beforeForm.isEmpty ? null : beforeForm,
            afterForm.isEmpty ? null : afterForm,
          ),
          before: beforeForm.isEmpty ? null : '${beforeForm.length} field(s)',
          after: afterForm.isEmpty ? null : '${afterForm.length} field(s)',
        ),
      );
    }
    return SemanticDiff(out);
  }
}

/// Diffs the workspace-serialized fields of a folder node (name, favorite,
/// variables, child order). Description is not persisted, so it is not diffed.
class FolderNodeDiff {
  const FolderNodeDiff._();

  static SemanticDiff diff(
    CollectionNodeEntity? before,
    CollectionNodeEntity? after,
  ) {
    final out = <FieldChange>[];
    _scalar(out, 'name', before?.name, after?.name);
    _scalar(
      out,
      'favorite',
      before == null ? null : '${before.isFavorite}',
      after == null ? null : '${after.isFavorite}',
    );
    _mapPerKey(
      out,
      'variable',
      before?.variables ?? const {},
      after?.variables ?? const {},
    );

    final beforeOrder = before?.children.map((c) => c.name).toList() ?? const [];
    final afterOrder = after?.children.map((c) => c.name).toList() ?? const [];
    if (!_listEq.equals(beforeOrder, afterOrder)) {
      out.add(
        FieldChange(
          field: 'child order',
          kind: ChangeKind.changed,
          before: beforeOrder.join(', '),
          after: afterOrder.join(', '),
        ),
      );
    }
    return SemanticDiff(out);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/collections/domain/logic/semantic_diff_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/collections/domain/logic/semantic_diff.dart test/features/collections/domain/logic/semantic_diff_test.dart
git commit -m "feat(git): semantic diff engine for request/folder nodes"
```

---

### Task 2: `GitService` (web-gated CLI wrapper)

**Files:**
- Create: `lib/core/git/git_service.dart`, `lib/core/git/git_service_io.dart`, `lib/core/git/git_service_stub.dart`
- Test: `test/core/git/git_service_io_test.dart`

**Interfaces:**
- Produces:
  - `class GitStatusEntry { final String indexStatus; final String worktreeStatus; final String path; final String? renamedFrom; bool get isStaged; bool get isUntracked; }` (statuses are single-char; `' '` = unmodified, `'?'` = untracked).
  - `class GitException implements Exception { GitException(this.message, {this.exitCode}); }`
  - `abstract class GitService { Future<bool> isAvailable(); Future<bool> isRepo(String root); Future<void> init(String root); Future<String?> currentBranch(String root); Future<List<GitStatusEntry>> status(String root); Future<String?> headContent(String root, String path); Future<String?> workingContent(String root, String path); Future<void> stage(String root, List<String> paths); Future<void> unstage(String root, List<String> paths); Future<void> commit(String root, String message); }`
  - `GitService createGitService();`

- [ ] **Step 1: Write the failing test**

Create `test/core/git/git_service_io_test.dart`:

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

  setUp(() async {
    git = createGitService();
    tmp = await Directory.systemTemp.createTemp('getman_git_test');
    // Deterministic identity for commits in this repo only.
    await Process.run('git', ['init'], workingDirectory: tmp.path);
    await Process.run('git', ['config', 'user.email', 't@t.dev'], workingDirectory: tmp.path);
    await Process.run('git', ['config', 'user.name', 'T'], workingDirectory: tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('isRepo true for an initialized dir', () async {
    if (!await gitPresent()) return; // skip when git missing
    expect(await git.isRepo(tmp.path), isTrue);
  });

  test('status reports an untracked file, then staged after stage()', () async {
    if (!await gitPresent()) return;
    File('${tmp.path}/a.req.json').writeAsStringSync('{"x":1}');
    var st = await git.status(tmp.path);
    final untracked = st.firstWhere((e) => e.path == 'a.req.json');
    expect(untracked.isUntracked, isTrue);
    expect(untracked.isStaged, isFalse);

    await git.stage(tmp.path, ['a.req.json']);
    st = await git.status(tmp.path);
    expect(st.firstWhere((e) => e.path == 'a.req.json').isStaged, isTrue);
  });

  test('headContent returns committed content; commit clears status', () async {
    if (!await gitPresent()) return;
    File('${tmp.path}/a.req.json').writeAsStringSync('v1');
    await git.stage(tmp.path, ['a.req.json']);
    await git.commit(tmp.path, 'first');
    expect(await git.status(tmp.path), isEmpty);
    expect(await git.headContent(tmp.path, 'a.req.json'), 'v1');

    File('${tmp.path}/a.req.json').writeAsStringSync('v2');
    expect(await git.workingContent(tmp.path, 'a.req.json'), 'v2');
    // HEAD still has v1 until the next commit.
    expect(await git.headContent(tmp.path, 'a.req.json'), 'v1');
  });

  test('unstage removes a file from the index', () async {
    if (!await gitPresent()) return;
    File('${tmp.path}/a.req.json').writeAsStringSync('x');
    await git.stage(tmp.path, ['a.req.json']);
    await git.unstage(tmp.path, ['a.req.json']);
    expect(await git.status(tmp.path).then((s) => s.first.isStaged), isFalse);
  });

  test('headContent returns null for a path absent at HEAD', () async {
    if (!await gitPresent()) return;
    expect(await git.headContent(tmp.path, 'nope.json'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/git/git_service_io_test.dart`
Expected: FAIL — `git_service.dart` does not exist.

- [ ] **Step 3: Create interface + conditional export**

Create `lib/core/git/git_service.dart`:

```dart
/// A change entry from `git status --porcelain`. Statuses are single chars:
/// `' '` unmodified, `'M'` modified, `'A'` added, `'D'` deleted, `'R'` renamed,
/// `'?'` untracked (both columns `'?'`).
class GitStatusEntry {
  const GitStatusEntry({
    required this.indexStatus,
    required this.worktreeStatus,
    required this.path,
    this.renamedFrom,
  });
  final String indexStatus;
  final String worktreeStatus;
  final String path;
  final String? renamedFrom;

  bool get isUntracked => indexStatus == '?' && worktreeStatus == '?';
  bool get isStaged => !isUntracked && indexStatus != ' ';
}

/// A git command failure (non-zero exit, or git missing).
class GitException implements Exception {
  GitException(this.message, {this.exitCode});
  final String message;
  final int? exitCode;
  @override
  String toString() => 'GitException($message)';
}

/// Drives the system `git` CLI over a workspace directory. The `_io`
/// implementation is the sole `dart:io` importer; web gets the no-op stub.
abstract class GitService {
  Future<bool> isAvailable();
  Future<bool> isRepo(String root);
  Future<void> init(String root);
  Future<String?> currentBranch(String root);
  Future<List<GitStatusEntry>> status(String root);

  /// Content of [path] at HEAD, or null if it does not exist there.
  Future<String?> headContent(String root, String path);

  /// Current working-tree content of [path], or null if it does not exist.
  Future<String?> workingContent(String root, String path);

  Future<void> stage(String root, List<String> paths);
  Future<void> unstage(String root, List<String> paths);
  Future<void> commit(String root, String message);
}

export 'git_service_stub.dart'
    if (dart.library.io) 'git_service_io.dart'
    show createGitService;
```

> Note: a file cannot both declare classes and re-export in a way that shadows
> them, but `export ... show createGitService` only re-exports the factory
> symbol from the io/stub file, so the `GitService`/`GitStatusEntry`/
> `GitException` declared above remain the canonical types. The io/stub files
> import this file to implement `GitService`.

Create `lib/core/git/git_service_stub.dart`:

```dart
import 'package:getman/core/git/git_service.dart';

GitService createGitService() => _StubGitService();

/// Web build: git is unavailable; every op is a no-op / reports unavailable.
class _StubGitService implements GitService {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> isRepo(String root) async => false;
  @override
  Future<void> init(String root) async {}
  @override
  Future<String?> currentBranch(String root) async => null;
  @override
  Future<List<GitStatusEntry>> status(String root) async => const [];
  @override
  Future<String?> headContent(String root, String path) async => null;
  @override
  Future<String?> workingContent(String root, String path) async => null;
  @override
  Future<void> stage(String root, List<String> paths) async {}
  @override
  Future<void> unstage(String root, List<String> paths) async {}
  @override
  Future<void> commit(String root, String message) async {}
}
```

Create `lib/core/git/git_service_io.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:getman/core/git/git_service.dart';

GitService createGitService() => _IoGitService();

class _IoGitService implements GitService {
  Future<ProcessResult> _run(
    String root,
    List<String> args, {
    bool allowFailure = false,
  }) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure && result.exitCode != 0) {
      throw GitException(
        (result.stderr as String).trim().isEmpty
            ? 'git ${args.first} failed'
            : (result.stderr as String).trim(),
        exitCode: result.exitCode,
      );
    }
    return result;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final r = await Process.run('git', ['--version']);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isRepo(String root) async {
    if (!Directory(root).existsSync()) return false;
    final r = await _run(
      root,
      ['rev-parse', '--is-inside-work-tree'],
      allowFailure: true,
    );
    return r.exitCode == 0 && (r.stdout as String).trim() == 'true';
  }

  @override
  Future<void> init(String root) async {
    await Directory(root).create(recursive: true);
    await _run(root, ['init']);
  }

  @override
  Future<String?> currentBranch(String root) async {
    final r = await _run(root, ['branch', '--show-current'], allowFailure: true);
    final name = (r.stdout as String).trim();
    return name.isEmpty ? null : name;
  }

  @override
  Future<List<GitStatusEntry>> status(String root) async {
    final r = await _run(root, ['status', '--porcelain=v1', '-z']);
    return _parseStatusZ(r.stdout as String);
  }

  @override
  Future<String?> headContent(String root, String path) async {
    final r = await _run(root, ['show', 'HEAD:$path'], allowFailure: true);
    return r.exitCode == 0 ? r.stdout as String : null;
  }

  @override
  Future<String?> workingContent(String root, String path) async {
    final file = File('$root/$path');
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  @override
  Future<void> stage(String root, List<String> paths) async {
    if (paths.isEmpty) return;
    await _run(root, ['add', '--', ...paths]);
  }

  @override
  Future<void> unstage(String root, List<String> paths) async {
    if (paths.isEmpty) return;
    // `git reset` fails on a repo with no commits yet; fall back to rm --cached.
    final r = await _run(
      root,
      ['reset', '-q', 'HEAD', '--', ...paths],
      allowFailure: true,
    );
    if (r.exitCode != 0) {
      await _run(root, ['rm', '--cached', '-q', '--', ...paths], allowFailure: true);
    }
  }

  @override
  Future<void> commit(String root, String message) async {
    await _run(root, ['commit', '-m', message]);
  }

  /// Parses `git status --porcelain=v1 -z`. Records are NUL-terminated; a
  /// rename record (`R`/`C`) is followed by a second NUL-token holding the
  /// source path.
  static List<GitStatusEntry> _parseStatusZ(String raw) {
    final tokens = raw.split(' ')..removeWhere((t) => t.isEmpty);
    final out = <GitStatusEntry>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.length < 4) continue;
      final index = token[0];
      final worktree = token[1];
      final path = token.substring(3);
      String? renamedFrom;
      if (index == 'R' || index == 'C') {
        if (i + 1 < tokens.length) renamedFrom = tokens[++i];
      }
      out.add(
        GitStatusEntry(
          indexStatus: index,
          worktreeStatus: worktree,
          path: path,
          renamedFrom: renamedFrom,
        ),
      );
    }
    return out;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/git/git_service_io_test.dart`
Expected: PASS (tests self-skip if `git` is not installed).

- [ ] **Step 5: Commit**

```bash
git add lib/core/git test/core/git
git commit -m "feat(git): GitService CLI wrapper (web-gated) with status/diff/stage/commit"
```

---

### Task 3: `WorkspaceReviewService` + review entities (pure)

**Files:**
- Create: `lib/features/collections/domain/entities/review_entry.dart`
- Create: `lib/features/collections/data/services/workspace_review_service.dart`
- Test: `test/features/collections/data/services/workspace_review_service_test.dart`

**Interfaces:**
- Consumes: `GitService`, `GitStatusEntry` (Task 2); `SemanticDiff`, `RequestConfigDiff`, `FolderNodeDiff` (Task 1); `WorkspaceCollectionSerializer.requestFromJson/folderFromJson`.
- Produces:
  - `enum NodeKind { request, folder, workspaceOrder }`
  - `enum ChangeType { added, modified, deleted }`
  - `class ReviewEntry { final String path; final NodeKind nodeKind; final ChangeType changeType; final String displayName; final bool staged; final SemanticDiff diff; }`
  - `class ReviewResult { final bool gitAvailable; final bool repoExists; final String? branch; final List<ReviewEntry> entries; }`
  - `class WorkspaceReviewService { WorkspaceReviewService(this._git); Future<ReviewResult> review(String root); Future<void> stage/unstage(String root, String path); Future<void> commit(String root, String message); Future<void> init(String root); }`

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/data/services/workspace_review_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:mocktail/mocktail.dart';

class _MockGit extends Mock implements GitService {}

String reqJson(String name, {String method = 'GET', String url = 'https://a'}) =>
    jsonEncode({
      'id': 'id-$name',
      'name': name,
      'isFavorite': false,
      'request': {'id': 'id-$name', 'method': method, 'url': url, 'headers': {}, 'body': '', 'bodyType': 'raw', 'auth': {}},
    });

void main() {
  late _MockGit git;
  late WorkspaceReviewService service;
  const root = '/ws';

  setUp(() {
    git = _MockGit();
    service = WorkspaceReviewService(git);
    when(() => git.isAvailable()).thenAnswer((_) async => true);
    when(() => git.isRepo(root)).thenAnswer((_) async => true);
    when(() => git.currentBranch(root)).thenAnswer((_) async => 'main');
  });

  test('reports git unavailable', () async {
    when(() => git.isAvailable()).thenAnswer((_) async => false);
    final r = await service.review(root);
    expect(r.gitAvailable, isFalse);
    expect(r.entries, isEmpty);
  });

  test('a modified request produces a request entry with a semantic diff', () async {
    when(() => git.status(root)).thenAnswer((_) async => const [
      GitStatusEntry(indexStatus: ' ', worktreeStatus: 'M', path: 'get-user.req.json'),
    ]);
    when(() => git.headContent(root, 'get-user.req.json'))
        .thenAnswer((_) async => reqJson('Get User'));
    when(() => git.workingContent(root, 'get-user.req.json'))
        .thenAnswer((_) async => reqJson('Get User', method: 'POST'));

    final r = await service.review(root);
    final entry = r.entries.single;
    expect(entry.nodeKind, NodeKind.request);
    expect(entry.changeType, ChangeType.modified);
    expect(entry.displayName, 'Get User');
    expect(entry.staged, isFalse);
    expect(entry.diff.changes.any((c) => c.field == 'method'), isTrue);
  });

  test('an untracked (added) request is changeType added and staged=false', () async {
    when(() => git.status(root)).thenAnswer((_) async => const [
      GitStatusEntry(indexStatus: '?', worktreeStatus: '?', path: 'new.req.json'),
    ]);
    when(() => git.headContent(root, 'new.req.json')).thenAnswer((_) async => null);
    when(() => git.workingContent(root, 'new.req.json'))
        .thenAnswer((_) async => reqJson('New'));

    final entry = (await service.review(root)).entries.single;
    expect(entry.changeType, ChangeType.added);
    expect(entry.staged, isFalse);
  });

  test('the manifest maps to a workspaceOrder entry', () async {
    when(() => git.status(root)).thenAnswer((_) async => const [
      GitStatusEntry(indexStatus: 'M', worktreeStatus: ' ', path: '.getman/workspace.json'),
    ]);
    when(() => git.headContent(root, any())).thenAnswer((_) async => '{}');
    when(() => git.workingContent(root, any())).thenAnswer((_) async => '{}');

    final entry = (await service.review(root)).entries.single;
    expect(entry.nodeKind, NodeKind.workspaceOrder);
    expect(entry.staged, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/collections/data/services/workspace_review_service_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Create the entities**

Create `lib/features/collections/domain/entities/review_entry.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

enum NodeKind { request, folder, workspaceOrder }

enum ChangeType { added, modified, deleted }

/// One reviewable change: a node (request/folder/order file), how it changed,
/// whether it is staged in the git index, and its semantic diff.
class ReviewEntry extends Equatable {
  const ReviewEntry({
    required this.path,
    required this.nodeKind,
    required this.changeType,
    required this.displayName,
    required this.staged,
    required this.diff,
  });
  final String path;
  final NodeKind nodeKind;
  final ChangeType changeType;
  final String displayName;
  final bool staged;
  final SemanticDiff diff;

  @override
  List<Object?> get props => [path, nodeKind, changeType, displayName, staged, diff];
}

/// The result of reviewing a workspace: git availability + the change set.
class ReviewResult extends Equatable {
  const ReviewResult({
    required this.gitAvailable,
    required this.repoExists,
    required this.branch,
    required this.entries,
  });
  final bool gitAvailable;
  final bool repoExists;
  final String? branch;
  final List<ReviewEntry> entries;

  static const empty = ReviewResult(
    gitAvailable: false,
    repoExists: false,
    branch: null,
    entries: [],
  );

  @override
  List<Object?> get props => [gitAvailable, repoExists, branch, entries];
}
```

- [ ] **Step 3b: Create the service**

Create `lib/features/collections/data/services/workspace_review_service.dart`:

```dart
import 'dart:convert';

import 'package:getman/core/git/git_service.dart';
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

/// Composes [GitService] + the workspace serializer into a reviewable change
/// set. Pure of `dart:io` — all filesystem/git access goes through [GitService].
class WorkspaceReviewService {
  WorkspaceReviewService(this._git);
  final GitService _git;

  static const String _metaDir = '.getman';
  static const String _manifest = 'workspace.json';
  static const String _folderMeta = '.folder.json';
  static const String _reqExt = '.req.json';

  Future<ReviewResult> review(String root) async {
    if (!await _git.isAvailable()) return ReviewResult.empty;
    if (!await _git.isRepo(root)) {
      return const ReviewResult(
        gitAvailable: true,
        repoExists: false,
        branch: null,
        entries: [],
      );
    }
    final branch = await _git.currentBranch(root);
    final status = await _git.status(root);
    final entries = <ReviewEntry>[];
    for (final s in status) {
      final entry = await _entryFor(root, s);
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return ReviewResult(
      gitAvailable: true,
      repoExists: true,
      branch: branch,
      entries: entries,
    );
  }

  Future<void> init(String root) => _git.init(root);
  Future<void> stage(String root, String path) => _git.stage(root, [path]);
  Future<void> unstage(String root, String path) => _git.unstage(root, [path]);
  Future<void> commit(String root, String message) =>
      _git.commit(root, message);

  Future<ReviewEntry?> _entryFor(String root, GitStatusEntry s) async {
    final path = s.path;
    final headRaw = await _git.headContent(root, path);
    final workRaw = await _git.workingContent(root, path);
    final changeType = workRaw == null
        ? ChangeType.deleted
        : headRaw == null
        ? ChangeType.added
        : ChangeType.modified;

    if (path == '$_metaDir/$_manifest') {
      return ReviewEntry(
        path: path,
        nodeKind: NodeKind.workspaceOrder,
        changeType: changeType,
        displayName: 'Workspace order',
        staged: s.isStaged,
        diff: const SemanticDiff([
          FieldChange(field: 'root order', kind: ChangeKind.changed),
        ]),
      );
    }

    if (path.endsWith('/$_folderMeta') || path == _folderMeta) {
      final before = _parseFolder(headRaw);
      final after = _parseFolder(workRaw);
      return ReviewEntry(
        path: path,
        nodeKind: NodeKind.folder,
        changeType: changeType,
        displayName: (after ?? before)?.name ?? 'Folder',
        staged: s.isStaged,
        diff: FolderNodeDiff.diff(before, after),
      );
    }

    if (path.endsWith(_reqExt)) {
      final before = _parseRequest(headRaw);
      final after = _parseRequest(workRaw);
      return ReviewEntry(
        path: path,
        nodeKind: NodeKind.request,
        changeType: changeType,
        displayName: (after ?? before)?.name ?? 'Request',
        staged: s.isStaged,
        diff: RequestConfigDiff.diff(before?.config, after?.config),
      );
    }
    return null; // non-workspace file — ignore
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  static _RequestNode? _parseRequest(String? raw) {
    final json = _decode(raw);
    if (json == null) return null;
    final node = WorkspaceCollectionSerializer.requestFromJson(json);
    return _RequestNode(node.name, node.config);
  }

  static _FolderNode? _parseFolder(String? raw) {
    final json = _decode(raw);
    if (json == null) return null;
    return _FolderNode(WorkspaceCollectionSerializer.folderFromJson(json, const []));
  }
}
```

> Add these tiny private adapters at the bottom of the same file so the service
> returns entity types without leaking `CollectionNodeEntity` construction
> details into `_entryFor`:

```dart
class _RequestNode {
  const _RequestNode(this.name, this.config);
  final String name;
  final Object? config; // HttpRequestConfigEntity?
}

class _FolderNode {
  const _FolderNode(this.node);
  final Object node;
}
```

> **Implementer note:** the two adapter classes above are a starting sketch —
> replace `Object`/`Object?` with the real types by importing
> `package:getman/core/domain/entities/request_config_entity.dart` and
> `package:getman/features/collections/domain/entities/collection_node_entity.dart`,
> and have `_parseFolder` return the `CollectionNodeEntity` directly so
> `FolderNodeDiff.diff(before, after)` receives `CollectionNodeEntity?`. Keep
> `RequestConfigDiff.diff` receiving `HttpRequestConfigEntity?` (`node.config`).
> The test above pins the required behavior; make the types concrete to satisfy
> analyzer/`always_declare_return_types`.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/collections/data/services/workspace_review_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/collections/domain/entities/review_entry.dart lib/features/collections/data/services/workspace_review_service.dart test/features/collections/data/services/workspace_review_service_test.dart
git commit -m "feat(git): WorkspaceReviewService mapping git status to semantic review entries"
```

---

### Task 4: `ReviewBloc`

**Files:**
- Create: `lib/features/collections/presentation/bloc/review_event.dart`, `review_state.dart`, `review_bloc.dart`
- Test: `test/features/collections/presentation/bloc/review_bloc_test.dart`

**Interfaces:**
- Consumes: `WorkspaceReviewService`, `ReviewResult`, `ReviewEntry` (Task 3).
- Produces:
  - Events: `LoadReview(String root)`, `StageNode(String root, String path)`, `UnstageNode(String root, String path)`, `SelectEntry(String path)`, `Commit(String root, String message)`, `InitRepo(String root)`.
  - `enum ReviewStatus { initial, loading, ready, committing, error }`
  - `ReviewState { ReviewStatus status; bool gitAvailable; bool repoExists; String? branch; List<ReviewEntry> entries; String? selectedPath; String? errorMessage; }` with `stagedCount`.

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/presentation/bloc/review_bloc_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements WorkspaceReviewService {}

void main() {
  late _MockService service;
  const root = '/ws';
  const entry = ReviewEntry(
    path: 'a.req.json',
    nodeKind: NodeKind.request,
    changeType: ChangeType.modified,
    displayName: 'A',
    staged: false,
    diff: SemanticDiff([FieldChange(field: 'method', kind: ChangeKind.changed, before: 'GET', after: 'POST')]),
  );
  const result = ReviewResult(gitAvailable: true, repoExists: true, branch: 'main', entries: [entry]);

  setUp(() {
    service = _MockService();
    when(() => service.review(root)).thenAnswer((_) async => result);
    when(() => service.stage(root, any())).thenAnswer((_) async {});
    when(() => service.commit(root, any())).thenAnswer((_) async {});
  });

  blocTest<ReviewBloc, ReviewState>(
    'LoadReview → ready with entries',
    build: () => ReviewBloc(service: service),
    act: (b) => b.add(const LoadReview(root)),
    verify: (b) {
      expect(b.state.status, ReviewStatus.ready);
      expect(b.state.entries.single.displayName, 'A');
      expect(b.state.branch, 'main');
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'StageNode stages then reloads',
    build: () => ReviewBloc(service: service),
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const StageNode(root, 'a.req.json'));
    },
    verify: (b) {
      verify(() => service.stage(root, 'a.req.json')).called(1);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'Commit calls the service and reloads',
    build: () => ReviewBloc(service: service),
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const Commit(root, 'msg'));
    },
    verify: (b) {
      verify(() => service.commit(root, 'msg')).called(1);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'review failure → error status',
    build: () {
      when(() => service.review(root)).thenThrow(Exception('boom'));
      return ReviewBloc(service: service);
    },
    act: (b) => b.add(const LoadReview(root)),
    verify: (b) => expect(b.state.status, ReviewStatus.error),
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/bloc/review_bloc_test.dart`
Expected: FAIL — bloc files do not exist.

- [ ] **Step 3: Create event, state, bloc**

Create `lib/features/collections/presentation/bloc/review_event.dart`:

```dart
import 'package:equatable/equatable.dart';

abstract class ReviewEvent extends Equatable {
  const ReviewEvent();
  @override
  List<Object?> get props => [];
}

class LoadReview extends ReviewEvent {
  const LoadReview(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class StageNode extends ReviewEvent {
  const StageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

class UnstageNode extends ReviewEvent {
  const UnstageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

class SelectEntry extends ReviewEvent {
  const SelectEntry(this.path);
  final String path;
  @override
  List<Object?> get props => [path];
}

class Commit extends ReviewEvent {
  const Commit(this.root, this.message);
  final String root;
  final String message;
  @override
  List<Object?> get props => [root, message];
}

class InitRepo extends ReviewEvent {
  const InitRepo(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}
```

Create `lib/features/collections/presentation/bloc/review_state.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';

enum ReviewStatus { initial, loading, ready, committing, error }

class ReviewState extends Equatable {
  const ReviewState({
    this.status = ReviewStatus.initial,
    this.gitAvailable = true,
    this.repoExists = true,
    this.branch,
    this.entries = const [],
    this.selectedPath,
    this.errorMessage,
  });

  final ReviewStatus status;
  final bool gitAvailable;
  final bool repoExists;
  final String? branch;
  final List<ReviewEntry> entries;
  final String? selectedPath;
  final String? errorMessage;

  int get stagedCount => entries.where((e) => e.staged).length;

  ReviewState copyWith({
    ReviewStatus? status,
    bool? gitAvailable,
    bool? repoExists,
    String? branch,
    List<ReviewEntry>? entries,
    String? selectedPath,
    String? errorMessage,
  }) => ReviewState(
    status: status ?? this.status,
    gitAvailable: gitAvailable ?? this.gitAvailable,
    repoExists: repoExists ?? this.repoExists,
    branch: branch ?? this.branch,
    entries: entries ?? this.entries,
    selectedPath: selectedPath ?? this.selectedPath,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => [
    status,
    gitAvailable,
    repoExists,
    branch,
    entries,
    selectedPath,
    errorMessage,
  ];
}
```

Create `lib/features/collections/presentation/bloc/review_bloc.dart`:

```dart
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';

/// Drives the Review Changes dialog over [WorkspaceReviewService]. git's index
/// is the source of truth, so stage/unstage/commit re-run the review.
class ReviewBloc extends Bloc<ReviewEvent, ReviewState> {
  ReviewBloc({required WorkspaceReviewService service})
    : _service = service,
      super(const ReviewState()) {
    on<LoadReview>(_onLoad);
    on<StageNode>(_onStage);
    on<UnstageNode>(_onUnstage);
    on<SelectEntry>(_onSelect);
    on<Commit>(_onCommit);
    on<InitRepo>(_onInit);
  }

  final WorkspaceReviewService _service;

  Future<void> _onLoad(LoadReview event, Emitter<ReviewState> emit) async {
    emit(state.copyWith(status: ReviewStatus.loading));
    try {
      final r = await _service.review(event.root);
      final selected = r.entries.any((e) => e.path == state.selectedPath)
          ? state.selectedPath
          : r.entries.isNotEmpty
          ? r.entries.first.path
          : null;
      emit(
        state.copyWith(
          status: ReviewStatus.ready,
          gitAvailable: r.gitAvailable,
          repoExists: r.repoExists,
          branch: r.branch,
          entries: r.entries,
          selectedPath: selected,
        ),
      );
    } on Object catch (e) {
      log('review load failed: $e', name: 'ReviewBloc');
      emit(state.copyWith(status: ReviewStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> _onStage(StageNode event, Emitter<ReviewState> emit) async {
    try {
      await _service.stage(event.root, event.path);
    } on Object catch (e) {
      log('stage failed: $e', name: 'ReviewBloc');
    }
    add(LoadReview(event.root));
  }

  Future<void> _onUnstage(UnstageNode event, Emitter<ReviewState> emit) async {
    try {
      await _service.unstage(event.root, event.path);
    } on Object catch (e) {
      log('unstage failed: $e', name: 'ReviewBloc');
    }
    add(LoadReview(event.root));
  }

  void _onSelect(SelectEntry event, Emitter<ReviewState> emit) {
    emit(state.copyWith(selectedPath: event.path));
  }

  Future<void> _onCommit(Commit event, Emitter<ReviewState> emit) async {
    emit(state.copyWith(status: ReviewStatus.committing));
    try {
      await _service.commit(event.root, event.message);
    } on Object catch (e) {
      log('commit failed: $e', name: 'ReviewBloc');
      emit(state.copyWith(status: ReviewStatus.error, errorMessage: e.toString()));
      return;
    }
    add(LoadReview(event.root));
  }

  Future<void> _onInit(InitRepo event, Emitter<ReviewState> emit) async {
    try {
      await _service.init(event.root);
    } on Object catch (e) {
      log('init failed: $e', name: 'ReviewBloc');
    }
    add(LoadReview(event.root));
  }
}
```

- [ ] **Step 4: Run test + bloc_lint**

Run: `fvm flutter test test/features/collections/presentation/bloc/review_bloc_test.dart`
Expected: PASS.
Run: `fvm dart run bloc_tools:bloc lint lib`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/collections/presentation/bloc/review_event.dart lib/features/collections/presentation/bloc/review_state.dart lib/features/collections/presentation/bloc/review_bloc.dart test/features/collections/presentation/bloc/review_bloc_test.dart
git commit -m "feat(git): ReviewBloc driving review/stage/commit over the service"
```

---

### Task 5: DI registration + app-wide provider

**Files:**
- Modify: `lib/core/di/injection_container.dart`
- Modify: `lib/main.dart`
- Test: `test/features/collections/git_di_registration_test.dart`

**Interfaces:**
- Consumes: `createGitService()` (Task 2), `WorkspaceReviewService` (Task 3), `ReviewBloc` (Task 4); the existing `sl` GetIt instance.
- Produces: `sl<GitService>()`, `sl<WorkspaceReviewService>()`, `sl<ReviewBloc>()` resolve; `ReviewBloc` provided above `MaterialApp`.

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/git_di_registration_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';

void main() {
  test('git service, review service, and ReviewBloc are registered', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = await Directory.systemTemp.createTemp('getman_di');
    await di.init(storageDirectoryOverride: tmp.path);
    expect(di.sl.isRegistered<GitService>(), isTrue);
    expect(di.sl.isRegistered<WorkspaceReviewService>(), isTrue);
    expect(di.sl<ReviewBloc>(), isA<ReviewBloc>());
    await tmp.delete(recursive: true);
  });
}
```

> Match the `di.init(storageDirectoryOverride: …)` bootstrapping used by the
> existing MCP DI test (`test/features/mcp/di_registration_test.dart`); copy its
> setup verbatim if signatures differ.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/collections/git_di_registration_test.dart`
Expected: FAIL — not registered.

- [ ] **Step 3: Register in DI**

In `lib/core/di/injection_container.dart`, add imports (alphabetical in the `package:getman` group):

```dart
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
```

Then, near the other collections/service registrations (e.g. just after the `WorkspaceSyncService` registration around line 185):

```dart
    ..registerLazySingleton<GitService>(createGitService)
    ..registerLazySingleton(() => WorkspaceReviewService(sl()))
    ..registerFactory(() => ReviewBloc(service: sl()))
```

> `ReviewBloc` is a `registerFactory` (fresh per dialog open) — it holds
> per-session review state, not app-wide state.

- [ ] **Step 4: Provide the bloc in `main.dart`**

In `lib/main.dart`, add the import (alphabetical):

```dart
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
```

Then in the `MultiBlocProvider` `providers` list (near the other feature blocs):

```dart
          BlocProvider(create: (_) => di.sl<ReviewBloc>()),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `fvm flutter test test/features/collections/git_di_registration_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/di/injection_container.dart lib/main.dart test/features/collections/git_di_registration_test.dart
git commit -m "feat(git): register GitService + review service + ReviewBloc in DI"
```

---

### Task 6: `SemanticDiffView` widget

**Files:**
- Create: `lib/features/collections/presentation/widgets/semantic_diff_view.dart`
- Test: `test/features/collections/presentation/widgets/semantic_diff_view_test.dart`

**Interfaces:**
- Consumes: `SemanticDiff`, `FieldChange`, `ChangeKind` (Task 1); `LineDiff.diffText` + `DiffLineKind` (`lib/core/utils/line_diff.dart`); `context.appPalette` (`variableResolved`/`variableUnresolved` as add/remove accents), `context.appTypography.codeFontFamily`.
- Produces: `class SemanticDiffView extends StatelessWidget { const SemanticDiffView({required this.diff, super.key}); final SemanticDiff diff; }`

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/presentation/widgets/semantic_diff_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/presentation/widgets/semantic_diff_view.dart';

void main() {
  Widget host(SemanticDiff diff) => MaterialApp(
    theme: resolveTheme('classic')(Brightness.light),
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: SemanticDiffView(diff: diff)),
    ),
  );

  testWidgets('renders a field label and no overflow', (tester) async {
    await tester.pumpWidget(host(const SemanticDiff([
      FieldChange(field: 'method', kind: ChangeKind.changed, before: 'GET', after: 'POST'),
    ])));
    await tester.pumpAndSettle();
    expect(find.textContaining('method'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty diff shows a no-changes hint', (tester) async {
    await tester.pumpWidget(host(const SemanticDiff([])));
    expect(find.textContaining('No field-level changes'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/semantic_diff_view_test.dart`
Expected: FAIL — widget missing.

- [ ] **Step 3: Create the widget**

Create `lib/features/collections/presentation/widgets/semantic_diff_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

/// Read-only render of a [SemanticDiff]: one block per changed field. Multi-line
/// scalar values (e.g. body) render as a per-line add/remove diff.
class SemanticDiffView extends StatelessWidget {
  const SemanticDiffView({required this.diff, super.key});
  final SemanticDiff diff;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typo = context.appTypography;
    if (diff.isEmpty) {
      return Center(
        child: Text(
          'No field-level changes',
          style: TextStyle(fontWeight: typo.bodyWeight),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.all(layout.inputPadding),
      itemCount: diff.changes.length,
      separatorBuilder: (_, __) => SizedBox(height: layout.inputPadding),
      itemBuilder: (context, i) => _FieldBlock(change: diff.changes[i]),
    );
  }
}

class _FieldBlock extends StatelessWidget {
  const _FieldBlock({required this.change});
  final FieldChange change;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final typo = context.appTypography;
    final theme = Theme.of(context);
    final addColor = palette.variableResolved;
    final removeColor = palette.variableUnresolved;

    final label = switch (change.kind) {
      ChangeKind.added => '+ ${change.field}',
      ChangeKind.removed => '- ${change.field}',
      ChangeKind.changed => '~ ${change.field}',
    };
    final labelColor = switch (change.kind) {
      ChangeKind.added => addColor,
      ChangeKind.removed => removeColor,
      ChangeKind.changed => theme.colorScheme.onSurface,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: typo.titleWeight, color: labelColor),
        ),
        if (change.before != null || change.after != null) ...[
          const SizedBox(height: 4),
          ..._lineDiff(context, change.before ?? '', change.after ?? ''),
        ],
      ],
    );
  }

  List<Widget> _lineDiff(BuildContext context, String before, String after) {
    final palette = context.appPalette;
    final typo = context.appTypography;
    final theme = Theme.of(context);
    return LineDiff.diffText(before, after).map((line) {
      final (prefix, color) = switch (line.kind) {
        DiffLineKind.added => ('+ ', palette.variableResolved),
        DiffLineKind.removed => ('- ', palette.variableUnresolved),
        DiffLineKind.equal => ('  ', theme.colorScheme.onSurface),
      };
      return Text(
        '$prefix${line.text}',
        style: TextStyle(fontFamily: typo.codeFontFamily, color: color),
      );
    }).toList();
  }
}
```

- [ ] **Step 4: Run test + analyze**

Run: `fvm flutter test test/features/collections/presentation/widgets/semantic_diff_view_test.dart`
Expected: PASS.
Run: `fvm flutter analyze lib/features/collections/presentation/widgets/semantic_diff_view.dart`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/collections/presentation/widgets/semantic_diff_view.dart test/features/collections/presentation/widgets/semantic_diff_view_test.dart
git commit -m "feat(git): SemanticDiffView renders field-level node changes"
```

---

### Task 7: `ReviewChangesDialog` + trigger button

**Files:**
- Create: `lib/features/collections/presentation/widgets/review_changes_dialog.dart`
- Create: `lib/features/collections/presentation/widgets/review_changes_button.dart`
- Modify: `lib/features/collections/presentation/widgets/collections_list.dart` (mount the button in the header)
- Test: `test/features/collections/presentation/widgets/review_changes_dialog_test.dart`

**Interfaces:**
- Consumes: `ReviewBloc`/`ReviewState`/`ReviewStatus`/events (Task 4); `ReviewEntry`/`NodeKind`/`ChangeType` (Task 3); `SemanticDiffView` (Task 6); `ResponsiveDialogScaffold` (`lib/core/ui/widgets/responsive_dialog.dart`); `SettingsBloc` for `settings.workspacePath`.
- Produces: `ReviewChangesDialog.show(BuildContext, {required String root})`; `class ReviewChangesButton extends StatelessWidget` (reads workspacePath from `SettingsBloc`, hidden when null; loads review on open).

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/presentation/widgets/review_changes_dialog_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _MockReviewBloc extends MockBloc<ReviewEvent, ReviewState> implements ReviewBloc {}

void main() {
  late _MockReviewBloc bloc;

  const entry = ReviewEntry(
    path: 'a.req.json',
    nodeKind: NodeKind.request,
    changeType: ChangeType.modified,
    displayName: 'Get User',
    staged: false,
    diff: SemanticDiff([FieldChange(field: 'method', kind: ChangeKind.changed, before: 'GET', after: 'POST')]),
  );

  setUp(() => bloc = _MockReviewBloc());

  Widget host(ReviewState state) {
    when(() => bloc.state).thenReturn(state);
    return MaterialApp(
      theme: resolveTheme('classic')(Brightness.light),
      home: BlocProvider<ReviewBloc>.value(
        value: bloc,
        child: const Scaffold(body: ReviewChangesBody(root: '/ws')),
      ),
    );
  }

  testWidgets('lists changed nodes and shows the selected diff', (tester) async {
    await tester.pumpWidget(host(const ReviewState(
      status: ReviewStatus.ready,
      entries: [entry],
      selectedPath: 'a.req.json',
    )));
    await tester.pumpAndSettle();
    expect(find.text('Get User'), findsWidgets);
    expect(find.textContaining('method'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Commit disabled until a node is staged + message present', (tester) async {
    await tester.pumpWidget(host(const ReviewState(
      status: ReviewStatus.ready,
      entries: [entry],
      selectedPath: 'a.req.json',
    )));
    final commit = tester.widget<ElevatedButton>(find.byKey(const ValueKey('review_commit_button')));
    expect(commit.onPressed, isNull); // nothing staged yet
  });

  testWidgets('not a repo shows Initialize git', (tester) async {
    await tester.pumpWidget(host(const ReviewState(
      status: ReviewStatus.ready,
      repoExists: false,
    )));
    expect(find.textContaining('Initialize git'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/review_changes_dialog_test.dart`
Expected: FAIL — widget missing.

- [ ] **Step 3: Create the dialog**

Create `lib/features/collections/presentation/widgets/review_changes_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:getman/features/collections/presentation/widgets/semantic_diff_view.dart';

/// Opens the Review Changes dialog and dispatches the initial [LoadReview].
class ReviewChangesDialog {
  const ReviewChangesDialog._();

  static Future<void> show(BuildContext context, {required String root}) {
    context.read<ReviewBloc>().add(LoadReview(root));
    return ResponsiveDialog.show(
      context,
      builder: (_) => BlocProvider<ReviewBloc>.value(
        value: context.read<ReviewBloc>(),
        child: ReviewChangesBody(root: root),
      ),
    );
  }
}

/// The dialog content (public for widget testing).
class ReviewChangesBody extends StatefulWidget {
  const ReviewChangesBody({required this.root, super.key});
  final String root;

  @override
  State<ReviewChangesBody> createState() => _ReviewChangesBodyState();
}

class _ReviewChangesBodyState extends State<ReviewChangesBody> {
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  IconData _icon(ChangeType t) => switch (t) {
    ChangeType.added => Icons.add,
    ChangeType.deleted => Icons.remove,
    ChangeType.modified => Icons.edit,
  };

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocBuilder<ReviewBloc, ReviewState>(
      builder: (context, state) {
        return ResponsiveDialogScaffold(
          title: Text(
            state.branch == null ? 'REVIEW CHANGES' : 'REVIEW CHANGES · ${state.branch}',
          ),
          content: SizedBox(
            width: layout.dialogWidth * 1.8,
            height: layout.settingsDialogHeight,
            child: _body(context, state),
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

  Widget _body(BuildContext context, ReviewState state) {
    if (!state.gitAvailable) {
      return const Center(child: Text('git was not found on your PATH.'));
    }
    if (!state.repoExists) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This workspace is not a git repository.'),
            SizedBox(height: context.appLayout.inputPadding),
            ElevatedButton(
              onPressed: () =>
                  context.read<ReviewBloc>().add(InitRepo(widget.root)),
              child: const Text('Initialize git here'),
            ),
          ],
        ),
      );
    }
    if (state.entries.isEmpty) {
      return const Center(child: Text('No changes to review.'));
    }

    final selected = state.entries.firstWhere(
      (e) => e.path == state.selectedPath,
      orElse: () => state.entries.first,
    );
    final canCommit = state.stagedCount > 0 &&
        _message.text.trim().isNotEmpty &&
        state.status != ReviewStatus.committing;

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: context.appLayout.dialogWidth * 0.6,
                child: _NodeList(entries: state.entries, selectedPath: selected.path, root: widget.root, iconFor: _icon),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: SemanticDiffView(diff: selected.diff)),
            ],
          ),
        ),
        SizedBox(height: context.appLayout.inputPadding),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _message,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Commit message…'),
              ),
            ),
            SizedBox(width: context.appLayout.inputPadding),
            ElevatedButton(
              key: const ValueKey('review_commit_button'),
              onPressed: canCommit
                  ? () => context
                      .read<ReviewBloc>()
                      .add(Commit(widget.root, _message.text.trim()))
                  : null,
              child: Text(
                state.status == ReviewStatus.committing
                    ? 'COMMITTING…'
                    : 'COMMIT (${state.stagedCount})',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NodeList extends StatelessWidget {
  const _NodeList({
    required this.entries,
    required this.selectedPath,
    required this.root,
    required this.iconFor,
  });
  final List<ReviewEntry> entries;
  final String selectedPath;
  final String root;
  final IconData Function(ChangeType) iconFor;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          dense: true,
          selected: e.path == selectedPath,
          leading: Checkbox(
            value: e.staged,
            onChanged: (v) => context.read<ReviewBloc>().add(
              (v ?? false) ? StageNode(root, e.path) : UnstageNode(root, e.path),
            ),
          ),
          title: Text(e.displayName, overflow: TextOverflow.ellipsis),
          subtitle: Text(e.path, overflow: TextOverflow.ellipsis),
          trailing: Icon(iconFor(e.changeType), size: context.appLayout.smallIconSize),
          onTap: () => context.read<ReviewBloc>().add(SelectEntry(e.path)),
        );
      },
    );
  }
}
```

> **Implementer note:** confirm the `ResponsiveDialog.show` /
> `ResponsiveDialogScaffold` API against `lib/core/ui/widgets/responsive_dialog.dart`
> (a `show` helper exists near line 185). If the exact `show` signature differs,
> match it (this file already shows a working `ResponsiveDialogScaffold` usage:
> `lib/core/ui/widgets/response_diff_view.dart`). Do not hardcode sizes/colors —
> use `context.appLayout`/`appPalette`.

- [ ] **Step 3b: Create the trigger button**

Create `lib/features/collections/presentation/widgets/review_changes_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Header action that opens the Review Changes dialog. Hidden when no workspace
/// path is configured (and, via the GitService stub, inert on web).
class ReviewChangesButton extends StatelessWidget {
  const ReviewChangesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.workspacePath != n.settings.workspacePath,
      builder: (context, state) {
        final root = state.settings.workspacePath;
        if (root == null) return const SizedBox.shrink();
        return context.appDecoration.wrapInteractive(
          child: IconButton(
            key: const ValueKey('review_changes_button'),
            tooltip: 'Review changes',
            icon: Icon(Icons.rule, size: context.appLayout.iconSize),
            onPressed: () => ReviewChangesDialog.show(context, root: root),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 3c: Mount the button in the collections header**

In `lib/features/collections/presentation/widgets/collections_list.dart`, import the button and add `const ReviewChangesButton()` into the collections panel header row (next to the existing header actions / near the workspace tile). Keep it a single-line, surgical addition following the header's existing layout.

- [ ] **Step 4: Run test + analyze + custom_lint**

Run: `fvm flutter test test/features/collections/presentation/widgets/review_changes_dialog_test.dart`
Expected: PASS.
Run: `fvm flutter analyze lib/features/collections/presentation/widgets && fvm dart run custom_lint`
Expected: 0 issues (no GetIt in widgets, no hardcoded brand colors).

- [ ] **Step 5: Commit**

```bash
git add lib/features/collections/presentation/widgets/review_changes_dialog.dart lib/features/collections/presentation/widgets/review_changes_button.dart lib/features/collections/presentation/widgets/collections_list.dart test/features/collections/presentation/widgets/review_changes_dialog_test.dart
git commit -m "feat(git): Review Changes dialog + header trigger button"
```

---

### Task 8: Full verification + docs

- [ ] **Step 1: Run the entire verification bar**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```
Expected: analyze/custom_lint/bloc_lint "No issues"; format clean (commit if it changes files); all tests green.

- [ ] **Step 2: Fix anything that fails; re-run until all five are clean.**

- [ ] **Step 3: Wiki (deferred to merge)**

Do NOT push wiki changes for an unmerged feature. Note in the PR that a
**Version Control** wiki page (set a workspace → Review changes → stage →
commit; desktop-only, git required) is to be added when this merges, per the
keep-the-wiki-in-sync mandate. (The page will grow as Specs B/C/D land.)

- [ ] **Step 4: Final commit if formatting changed files**

```bash
git add -A && git commit -m "chore(git): format + final verification" || echo "nothing to commit"
```

---

## Self-Review

**Spec coverage:**
- `GitService` shell-out, web-gated, git-index staging → Task 2. ✓
- Semantic `RequestConfigDiff` + folder diff (serialized fields only; auth masked) → Task 1. ✓
- `WorkspaceReviewService` mapping status→nodes + diffs → Task 3. ✓
- `ReviewBloc` (load/stage/unstage/commit/init, index-as-truth reload) → Task 4. ✓
- DI + app-wide provider (+ stub on web) → Task 5. ✓
- `SemanticDiffView` (field changes + body line-diff) → Task 6. ✓
- `ReviewChangesDialog` (selective staging checkboxes, semantic diff pane, commit-message + enable logic, git-not-found / init empty states) + badged header trigger, desktop-gated via workspacePath → Task 7. ✓
- Boundaries (no push/pull/branch/merge; collections only; desktop only) — honored by construction; `GitService` exposes no such ops. ✓
- Verification bar + deferred wiki → Task 8. ✓

**Placeholder scan:** The `_RequestNode`/`_FolderNode` adapters in Task 3 are flagged as a sketch with an explicit implementer note to make types concrete; the pinning test enforces behavior. No `TBD`/"handle edge cases" in shipped code.

**Type consistency:** `SemanticDiff`/`FieldChange`/`ChangeKind`, `RequestConfigDiff.diff(HttpRequestConfigEntity?, …)`, `FolderNodeDiff.diff(CollectionNodeEntity?, …)`, `GitService`/`GitStatusEntry`/`createGitService`, `WorkspaceReviewService(GitService)` + `ReviewResult`/`ReviewEntry`/`NodeKind`/`ChangeType`, `ReviewBloc(service:)` + events/state used identically across Tasks 1–7. `LineDiff.diffText` + `DiffLineKind` match `line_diff.dart`; `WorkspaceCollectionSerializer.requestFromJson/folderFromJson` match the serializer.

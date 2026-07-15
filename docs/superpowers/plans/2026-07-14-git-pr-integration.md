# Git Pull Request Integration (Spec C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create GitHub pull requests and list the repo's open PRs (state +
checks) from inside Getman, via the `gh` CLI, without storing any credential.

**Architecture:** Three layers, mirroring Spec A/B. `GhService` (`lib/core/git/`,
the sole `dart:io` importer for `gh`, web-stubbed) shells out to `gh`. A domain
`PullRequestService` abstraction wraps it (+ the existing `BranchService` for the
push step); `PullRequestsBloc` depends only on that abstraction (required by the
`bloc_depends_on_abstractions` custom_lint rule). The dialog is reached from the
branch-chip menu; the after-create chip refresh is a widget-layer nudge, never
bloc→bloc.

**Tech Stack:** Flutter, flutter_bloc, get_it, equatable, mocktail, bloc_test,
`Process.run('gh', ...)` (no shell → no injection).

**Spec:** `docs/superpowers/specs/2026-07-14-git-pr-integration-design.md`

## Global Constraints

- Always invoke Flutter as `fvm flutter ...` / `fvm dart ...`. Never plain `flutter`.
- **Done-bar (all must be clean, separate passes):** `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib < /dev/null` (an update banner hides the verdict under a plain `tail` — grep for "issues found"), `( cd tools/getman_lints/example && fvm dart run custom_lint )`, `fvm dart format lib test tools`, and a 100% green `fvm flutter test`. Run analyze over the **whole repo**.
- **`dart:io` only in `*_io.dart` files** (`platform_io_outside_io_files`). `gh_service_io.dart` is the only place `gh` is executed.
- **Blocs must not import `data/`** (`bloc_depends_on_abstractions`). `PullRequestsBloc` depends on the domain `PullRequestService` abstraction only.
- **Domain layer is pure Dart + equatable** (`domain_no_infrastructure_imports`): no `package:flutter/`, `dart:io`, `dart:ui`, `package:dio/`, `package:hive_ce/`, or any sibling `data/` path.
- **No bloc→bloc coupling.** Cross-bloc coordination happens in a widget that holds both.
- **No `GetIt`/`sl<T>()` in widgets** (`avoid_get_it_in_widgets`). Widgets reach services via `BlocProvider` / `RepositoryProvider`.
- **No hardcoded sizes/colors/radii/weights** in widgets — read `context.appLayout`, `context.appPalette`, `context.appShape`, `context.appTypography`, `context.appDecoration`. No `Colors.black/white/red` literals (`avoid_hardcoded_brand_colors`); destructive/error tint via `colorScheme.error`.
- **Blocs log with `dart:developer`'s `log(msg, name: '<BlocName>')`**, never `debugPrint`.
- **Every `Equatable` class lists all its fields in `props`** (`equatable_props_complete`; the `// ignore:` for it, if needed, sits directly above the class declaration).
- **Snackbars via `showAppSnackBar(context, ...)`**, never inline `SnackBar`.
- Imports are `package:getman/...` — no relative imports; directives sorted alphabetically.
- Getman **stores no credentials** and never edits git config. Auth is whatever `gh auth` already provides.
- **Widget-test gotcha:** construct blocs INSIDE the `testWidgets` body, never in `setUp` (a bloc built in `setUp` sits outside the fake-async zone; its `await`s never resolve under `pumpAndSettle`). Provide `brutalistTheme(Brightness.light)` so `context.appLayout` etc. resolve.
- **Non-interactive `gh`:** every `gh` call runs via `Process.run` (non-tty), so `gh` never prompts on stdin — it errors instead, which we surface. We push before `gh pr create` precisely so `gh` never needs to prompt for a remote.
- Lines ≤ 80 chars.

---

## File Structure

**Create:**
- `lib/core/git/gh_service.dart` — abstract `GhService` + `PullRequestInfo` + `GhException` + the conditional export (createPr returns the URL string).
- `lib/core/git/gh_service_io.dart` — `_GhService` (shells out to `gh`).
- `lib/core/git/gh_service_stub.dart` — web no-op.
- `lib/core/git/gh_output_parser.dart` — **pure Dart** (no `dart:io`) parsers `parsePrList` / `rollupChecks` / `parsePrUrl`, imported by `gh_service_io.dart` and unit-tested directly (a test must not import the `dart:io` shell).
- `lib/core/utils/open_url.dart` — `Future<bool> openUrl(String)` over the existing `url_launcher` dependency (cross-platform; no `dart:io`, no new dependency).
- `lib/features/collections/domain/entities/pull_request.dart` — `PullRequestEntity`, enums `PrState`/`PrChecks`, `GhAvailability`, `PullRequestRef`.
- `lib/features/collections/domain/pull_request_service.dart` — abstract `PullRequestService`.
- `lib/features/collections/data/services/gh_pull_request_service.dart` — `GhPullRequestService implements PullRequestService`.
- `lib/features/collections/presentation/bloc/pull_requests_bloc.dart` / `pull_requests_event.dart` / `pull_requests_state.dart`.
- `lib/features/collections/presentation/widgets/pull_requests_dialog.dart`.
- Tests alongside each.

**Modify:**
- `lib/core/di/injection_container.dart` — register `GhService`, `PullRequestService`, `PullRequestsBloc`.
- `lib/main.dart` — provide `PullRequestsBloc` in the `MultiBlocProvider`.
- `lib/features/collections/presentation/widgets/branch_chip.dart` — add the `PULL REQUESTS…` menu item.

---

## Global constants used across tasks

Verbatim UI labels (also documented in the wiki, Task 8):
`PULL REQUESTS…`, `CREATE PULL REQUEST…`, `REFRESH`, `CREATE`, `CANCEL`,
`OPEN IN BROWSER`, `Create as draft`, `GitHub CLI (gh) not found`,
`INSTALL GH`, `Sign in with the GitHub CLI`, `No open pull requests.`,
`PR TITLE`, `Base branch`, `PR body (optional)`.

---

## Task 1: GhService — availability, auth, exceptions, and the conditional export

**Files:**
- Create: `lib/core/git/gh_service.dart`, `gh_service_io.dart`, `gh_service_stub.dart`
- Test: `test/core/git/gh_service_io_test.dart`

**Interfaces:**
- Produces: `abstract class GhService` with `Future<bool> isAvailable()`, `Future<bool> isAuthenticated(String root)`; `GhService createGhService()` (conditional export); `class GhException implements Exception { GhException(String message, {int? exitCode}); final String message; final int? exitCode; }`; and the value type `class PullRequestInfo` (fields defined here, used in Task 2). `createPr` (Task 3) returns `Future<String>` (the PR URL). `listPrs` (Task 2) returns `Future<List<PullRequestInfo>>`. `defaultBranch` (Task 2) returns `Future<String?>`.

- [ ] **Step 1: Write the abstract service + types + conditional export**

Create `lib/core/git/gh_service.dart`:

```dart
import 'package:getman/core/git/gh_service_stub.dart'
    if (dart.library.io) 'package:getman/core/git/gh_service_io.dart';

/// Talks to GitHub through the `gh` CLI. The single `dart:io` boundary for
/// `gh` lives in `gh_service_io.dart`; web builds get the stub. Rides on the
/// user's existing `gh auth` — Getman stores no credentials.
abstract class GhService {
  /// `gh --version` succeeds.
  Future<bool> isAvailable();

  /// `gh auth status` succeeds in [root] (a repo dir picks up its host).
  Future<bool> isAuthenticated(String root);

  /// Opens a PR for the current branch. Returns the PR URL printed by
  /// `gh pr create`. Throws [GhException] on any failure (incl. gh trying to
  /// prompt for a remote — we push first so it never should).
  Future<String> createPr(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  });

  /// Open PRs for the repo in [root], newest first as gh returns them.
  Future<List<PullRequestInfo>> listPrs(String root);

  /// The repo's default branch name (for the create form's base default), or
  /// null if it can't be determined.
  Future<String?> defaultBranch(String root);
}

GhService createGhService() => createGhServiceImpl();

/// One open pull request as reported by `gh pr list --json`. Primitive/string
/// fields only — the domain layer maps [state]/[checks] to its own enums.
class PullRequestInfo {
  const PullRequestInfo({
    required this.number,
    required this.title,
    required this.state,
    required this.url,
    required this.isDraft,
    required this.checks,
  });

  final int number;
  final String title;

  /// Raw gh state: `OPEN` / `MERGED` / `CLOSED`.
  final String state;
  final String url;
  final bool isDraft;

  /// Rolled-up check verdict: `none` / `pending` / `passing` / `failing`.
  final String checks;
}

class GhException implements Exception {
  GhException(this.message, {this.exitCode});
  final String message;
  final int? exitCode;

  @override
  String toString() => 'GhException($exitCode): $message';
}
```

- [ ] **Step 2: Write the web stub**

Create `lib/core/git/gh_service_stub.dart`:

```dart
import 'package:getman/core/git/gh_service.dart';

GhService createGhServiceImpl() => _StubGhService();

/// Web build: `gh` is a desktop binary, so every call is a no-op that reports
/// "not available".
class _StubGhService implements GhService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> isAuthenticated(String root) async => false;

  @override
  Future<String> createPr(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  }) async => throw GhException('gh is unavailable on web');

  @override
  Future<List<PullRequestInfo>> listPrs(String root) async => const [];

  @override
  Future<String?> defaultBranch(String root) async => null;
}
```

- [ ] **Step 3: Write the io implementation (availability + auth only for now)**

Create `lib/core/git/gh_service_io.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:getman/core/git/gh_service.dart';

GhService createGhServiceImpl() => _GhService();

class _GhService implements GhService {
  Future<ProcessResult> _run(
    String root,
    List<String> args, {
    bool allowFailure = false,
  }) async {
    final result = await Process.run(
      'gh',
      args,
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure && result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      throw GhException(
        err.isEmpty ? 'gh ${args.first} failed' : err,
        exitCode: result.exitCode,
      );
    }
    return result;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final r = await Process.run('gh', ['--version']);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isAuthenticated(String root) async {
    try {
      final r = await _run(root, ['auth', 'status'], allowFailure: true);
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<String> createPr(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  }) async {
    // Filled in Task 3.
    throw UnimplementedError();
  }

  @override
  Future<List<PullRequestInfo>> listPrs(String root) async {
    // Filled in Task 2.
    throw UnimplementedError();
  }

  @override
  Future<String?> defaultBranch(String root) async {
    // Filled in Task 2.
    throw UnimplementedError();
  }
}
```

- [ ] **Step 4: Write the test**

Create `test/core/git/gh_service_io_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/gh_service.dart';

void main() {
  late GhService gh;
  late Directory tmp;

  Future<bool> ghPresent() async => gh.isAvailable();

  setUp(() async {
    gh = createGhService();
    tmp = await Directory.systemTemp.createTemp('getman_gh_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('isAvailable reflects whether the gh binary runs', () async {
    // Either result is valid depending on the machine; the call must not throw.
    expect(await gh.isAvailable(), isA<bool>());
  });

  test('isAuthenticated is false in a non-repo dir when gh is present or '
      'absent (never throws)', () async {
    // In a bare temp dir with no gh host context, auth status is false; and if
    // gh is missing the catch returns false. Either way: no throw, a bool.
    final result = await gh.isAuthenticated(tmp.path);
    expect(result, isA<bool>());
    if (!await ghPresent()) expect(result, isFalse);
  });

  test('GhException carries the exit code and message', () {
    final e = GhException('boom', exitCode: 3);
    expect(e.message, 'boom');
    expect(e.exitCode, 3);
    expect(e.toString(), contains('boom'));
  });
}
```

- [ ] **Step 5: Run the tests, verify green**

Run: `fvm flutter test test/core/git/gh_service_io_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Gate + commit**

```bash
fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint
git add lib/core/git/gh_service.dart lib/core/git/gh_service_io.dart \
        lib/core/git/gh_service_stub.dart test/core/git/gh_service_io_test.dart
git commit -m "feat(git): GhService scaffold — availability, auth, gh exception"
```

---

## Task 2: GhService — listPrs + defaultBranch (gh --json parsing)

**Files:**
- Create: `lib/core/git/gh_output_parser.dart` (pure Dart parsers)
- Modify: `lib/core/git/gh_service_io.dart`
- Test: `test/core/git/gh_output_parser_test.dart`

**Interfaces:**
- Consumes: `PullRequestInfo` (Task 1).
- Produces: top-level pure functions in `gh_output_parser.dart` —
  `List<PullRequestInfo> parsePrList(String json)`,
  `String rollupChecks(Object? statusCheckRollup)`; `listPrs`/`defaultBranch`
  in `_GhService` wired to `gh` and delegating to the parser.

- [ ] **Step 1: Write the failing parser tests**

Create `test/core/git/gh_output_parser_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/gh_output_parser.dart';

void main() {
  test('parsePrList maps fields and rolls up passing checks', () {
    const json = '''
    [
      {"number":123,"title":"feat: x","state":"OPEN",
       "url":"https://github.com/o/r/pull/123","isDraft":false,
       "statusCheckRollup":[
         {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},
         {"__typename":"StatusContext","state":"SUCCESS"}]}
    ]''';
    final prs = parsePrList(json);
    expect(prs.single.number, 123);
    expect(prs.single.title, 'feat: x');
    expect(prs.single.state, 'OPEN');
    expect(prs.single.url, endsWith('/pull/123'));
    expect(prs.single.isDraft, isFalse);
    expect(prs.single.checks, 'passing');
  });

  test('rollupChecks: empty rollup is none', () {
    expect(rollupChecks(const <Object?>[]), 'none');
    expect(rollupChecks(null), 'none');
  });

  test('rollupChecks: an unfinished check is pending', () {
    final rollup = [
      {'__typename': 'CheckRun', 'status': 'IN_PROGRESS'},
      {'__typename': 'CheckRun', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'},
    ];
    expect(rollupChecks(rollup), 'pending');
  });

  test('rollupChecks: a completed failure (all finished) is failing', () {
    final rollup = [
      {'__typename': 'CheckRun', 'status': 'COMPLETED', 'conclusion': 'FAILURE'},
      {'__typename': 'StatusContext', 'state': 'SUCCESS'},
    ];
    expect(rollupChecks(rollup), 'failing');
  });

  test('rollupChecks: draft PR still parses', () {
    const json = '''
    [{"number":9,"title":"wip","state":"OPEN","url":"u","isDraft":true,
      "statusCheckRollup":[]}]''';
    expect(parsePrList(json).single.isDraft, isTrue);
    expect(parsePrList(json).single.checks, 'none');
  });
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `fvm flutter test test/core/git/gh_output_parser_test.dart`
Expected: FAIL — `parsePrList`/`rollupChecks` undefined.

- [ ] **Step 3: Implement the parser + wire the gh calls**

Create `lib/core/git/gh_output_parser.dart` (pure Dart — no `dart:io`) with
these top-level functions, and have `gh_service_io.dart` import it
(`import 'package:getman/core/git/gh_output_parser.dart';`) and delegate:

```dart
import 'dart:convert';

import 'package:getman/core/git/gh_service.dart';

/// Reduces a `statusCheckRollup` array to `none`/`pending`/`passing`/`failing`.
/// A check is unfinished when a CheckRun's `status` != `COMPLETED` or a
/// StatusContext's `state` is `PENDING`/`EXPECTED`. Pending wins over failing
/// wins over passing.
String rollupChecks(Object? statusCheckRollup) {
  if (statusCheckRollup is! List || statusCheckRollup.isEmpty) return 'none';
  var anyPending = false;
  var anyFailing = false;
  for (final raw in statusCheckRollup) {
    if (raw is! Map) continue;
    final type = raw['__typename'];
    if (type == 'CheckRun') {
      final status = raw['status'] as String?;
      if (status != 'COMPLETED') {
        anyPending = true;
      } else {
        final c = raw['conclusion'] as String?;
        if (c != 'SUCCESS' && c != 'NEUTRAL' && c != 'SKIPPED') {
          anyFailing = true;
        }
      }
    } else {
      // StatusContext
      final state = raw['state'] as String?;
      if (state == 'PENDING' || state == 'EXPECTED') {
        anyPending = true;
      } else if (state != 'SUCCESS') {
        anyFailing = true;
      }
    }
  }
  if (anyPending) return 'pending';
  if (anyFailing) return 'failing';
  return 'passing';
}

/// Parses `gh pr list --json number,title,state,url,isDraft,statusCheckRollup`.
List<PullRequestInfo> parsePrList(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List) return const [];
  return [
    for (final raw in decoded)
      if (raw is Map)
        PullRequestInfo(
          number: (raw['number'] as num?)?.toInt() ?? 0,
          title: raw['title'] as String? ?? '',
          state: raw['state'] as String? ?? 'OPEN',
          url: raw['url'] as String? ?? '',
          isDraft: raw['isDraft'] as bool? ?? false,
          checks: rollupChecks(raw['statusCheckRollup']),
        ),
  ];
}
```

Then in `_GhService`:

```dart
  @override
  Future<List<PullRequestInfo>> listPrs(String root) async {
    final r = await _run(root, [
      'pr',
      'list',
      '--state',
      'open',
      '--json',
      'number,title,state,url,isDraft,statusCheckRollup',
    ]);
    return parsePrList(r.stdout as String);
  }

  @override
  Future<String?> defaultBranch(String root) async {
    final r = await _run(root, [
      'repo',
      'view',
      '--json',
      'defaultBranchRef',
    ], allowFailure: true);
    if (r.exitCode != 0) return null;
    final decoded = jsonDecode(r.stdout as String);
    if (decoded is! Map) return null;
    final ref = decoded['defaultBranchRef'];
    if (ref is! Map) return null;
    return ref['name'] as String?;
  }
```

`parsePrList`/`rollupChecks` are top-level functions in the pure
`gh_output_parser.dart`; `_GhService` calls them. `dart:convert` is imported by
the parser file (shown above).

- [ ] **Step 4: Run tests, verify green**

Run: `fvm flutter test test/core/git/gh_output_parser_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Gate + commit**

```bash
fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint
git add lib/core/git/gh_output_parser.dart lib/core/git/gh_service_io.dart \
        test/core/git/gh_output_parser_test.dart
git commit -m "feat(git): gh pr list + defaultBranch parsing (statusCheckRollup)"
```

---

## Task 3: GhService — createPr

**Files:**
- Modify: `lib/core/git/gh_output_parser.dart` (add `parsePrUrl`), `lib/core/git/gh_service_io.dart` (wire `createPr`)
- Test: extend `test/core/git/gh_output_parser_test.dart`

**Interfaces:**
- Produces: `String parsePrUrl(String stdout)` (top-level in the pure parser,
  returns the last https URL gh printed) and the wired `createPr`.

- [ ] **Step 1: Write the failing test**

Add to `test/core/git/gh_output_parser_test.dart`:

```dart
  test('parsePrUrl returns the PR url gh printed on the last line', () {
    const out = 'Warning: 3 uncommitted changes\n'
        'https://github.com/o/r/pull/456\n';
    expect(parsePrUrl(out), 'https://github.com/o/r/pull/456');
  });

  test('parsePrUrl returns empty when no url is present', () {
    expect(parsePrUrl('nothing here'), '');
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `fvm flutter test test/core/git/gh_output_parser_test.dart`
Expected: FAIL — `parsePrUrl` undefined.

- [ ] **Step 3: Implement**

Top-level in `gh_output_parser.dart`:

```dart
/// The last `https://…` token gh printed — that is the created PR's URL.
String parsePrUrl(String stdout) {
  final match = RegExp(r'https://\S+').allMatches(stdout).toList();
  return match.isEmpty ? '' : match.last.group(0)!.trim();
}
```

Wire `createPr` in `_GhService`:

```dart
  @override
  Future<String> createPr(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  }) async {
    final r = await _run(root, [
      'pr',
      'create',
      '--base',
      base,
      '--title',
      title,
      '--body',
      body,
      if (draft) '--draft',
    ]);
    final url = parsePrUrl(r.stdout as String);
    if (url.isEmpty) {
      throw GhException('gh pr create did not return a PR url');
    }
    return url;
  }
```

- [ ] **Step 4: Run, verify green**

Run: `fvm flutter test test/core/git/gh_output_parser_test.dart`
Expected: PASS (7 tests total).

- [ ] **Step 5: Gate + commit**

```bash
fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint
git add lib/core/git/gh_output_parser.dart lib/core/git/gh_service_io.dart \
        test/core/git/gh_output_parser_test.dart
git commit -m "feat(git): gh pr create + PR url parsing"
```

---

## Task 4: Domain — PullRequestEntity, enums, PullRequestService abstraction

**Files:**
- Create: `lib/features/collections/domain/entities/pull_request.dart`
- Create: `lib/features/collections/domain/pull_request_service.dart`
- Test: `test/features/collections/domain/pull_request_test.dart`

**Interfaces:**
- Produces: enums `PrState { open, merged, closed }`, `PrChecks { none, pending, passing, failing }`, `GhAvailability { available, notInstalled, notAuthenticated }`; `class PullRequestEntity extends Equatable {int number; String title; PrState state; String url; bool isDraft; PrChecks checks;}`; `class PullRequestRef extends Equatable {int number; String url;}`; `abstract class PullRequestService { Future<GhAvailability> availability(String root); Future<List<PullRequestEntity>> list(String root); Future<PullRequestRef> create(String root, {required String base, required String title, required String body, required bool draft}); Future<String?> defaultBase(String root); }`.

- [ ] **Step 1: Write the entity test**

Create `test/features/collections/domain/pull_request_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';

void main() {
  test('PullRequestEntity equality is by value', () {
    const a = PullRequestEntity(
      number: 1,
      title: 't',
      state: PrState.open,
      url: 'u',
      isDraft: false,
      checks: PrChecks.passing,
    );
    const b = PullRequestEntity(
      number: 1,
      title: 't',
      state: PrState.open,
      url: 'u',
      isDraft: false,
      checks: PrChecks.passing,
    );
    expect(a, b);
  });

  test('PullRequestRef equality is by value', () {
    expect(
      const PullRequestRef(number: 5, url: 'u'),
      const PullRequestRef(number: 5, url: 'u'),
    );
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `fvm flutter test test/features/collections/domain/pull_request_test.dart`
Expected: FAIL — file/types undefined.

- [ ] **Step 3: Write the entities + enums**

Create `lib/features/collections/domain/entities/pull_request.dart`:

```dart
import 'package:equatable/equatable.dart';

/// A PR's lifecycle state (only `open` is listed in v1, but the mapping is
/// total so a created PR and future scopes are covered).
enum PrState { open, merged, closed }

/// Rolled-up CI verdict for a PR's head commit.
enum PrChecks { none, pending, passing, failing }

/// Whether the `gh` CLI can be used right now.
enum GhAvailability { available, notInstalled, notAuthenticated }

class PullRequestEntity extends Equatable {
  const PullRequestEntity({
    required this.number,
    required this.title,
    required this.state,
    required this.url,
    required this.isDraft,
    required this.checks,
  });

  final int number;
  final String title;
  final PrState state;
  final String url;
  final bool isDraft;
  final PrChecks checks;

  @override
  List<Object?> get props => [number, title, state, url, isDraft, checks];
}

/// The just-created PR — its number (parsed from the url) and url.
class PullRequestRef extends Equatable {
  const PullRequestRef({required this.number, required this.url});

  final int number;
  final String url;

  @override
  List<Object?> get props => [number, url];
}
```

- [ ] **Step 4: Write the service abstraction**

Create `lib/features/collections/domain/pull_request_service.dart`:

```dart
import 'package:getman/features/collections/domain/entities/pull_request.dart';

/// Domain gateway for GitHub pull-request operations. The data layer backs this
/// with the `gh` CLI; the bloc depends only on this abstraction.
abstract class PullRequestService {
  /// Whether `gh` is installed and authenticated for [root].
  Future<GhAvailability> availability(String root);

  /// Open PRs for the repo in [root].
  Future<List<PullRequestEntity>> list(String root);

  /// Pushes the current branch (setting upstream on first push) and opens a PR.
  Future<PullRequestRef> create(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  });

  /// The default base branch to preselect in the create form, or null.
  Future<String?> defaultBase(String root);
}
```

- [ ] **Step 5: Run, verify green**

Run: `fvm flutter test test/features/collections/domain/pull_request_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Gate + commit**

```bash
fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint
git add lib/features/collections/domain/entities/pull_request.dart \
        lib/features/collections/domain/pull_request_service.dart \
        test/features/collections/domain/pull_request_test.dart
git commit -m "feat(collections): PullRequestEntity + PullRequestService domain"
```

---

## Task 5: Data — GhPullRequestService + DI

**Files:**
- Create: `lib/features/collections/data/services/gh_pull_request_service.dart`
- Modify: `lib/core/di/injection_container.dart`
- Test: `test/features/collections/data/services/gh_pull_request_service_test.dart`

**Interfaces:**
- Consumes: `GhService` + `PullRequestInfo` (core), `BranchService` (domain, Spec B — has `push(String root)` which sets upstream on first push), `PullRequestService` + entities (Task 4).
- Produces: `class GhPullRequestService implements PullRequestService { GhPullRequestService(GhService gh, BranchService branch); }`.

Mapping rules the service owns: gh `state` string → `PrState`
(`MERGED`→merged, `CLOSED`→closed, else open); gh `checks` string → `PrChecks`
(`pending`/`passing`/`failing`/else none); the created PR's number is parsed
from its url's trailing path segment.

- [ ] **Step 1: Write the failing tests**

Create
`test/features/collections/data/services/gh_pull_request_service_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/gh_service.dart';
import 'package:getman/features/collections/data/services/gh_pull_request_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:mocktail/mocktail.dart';

class _MockGh extends Mock implements GhService {}

class _MockBranch extends Mock implements BranchService {}

void main() {
  const root = '/ws';
  late _MockGh gh;
  late _MockBranch branch;
  late GhPullRequestService service;

  setUp(() {
    gh = _MockGh();
    branch = _MockBranch();
    service = GhPullRequestService(gh, branch);
  });

  test('availability: notInstalled when gh is absent', () async {
    when(gh.isAvailable).thenAnswer((_) async => false);
    expect(await service.availability(root), GhAvailability.notInstalled);
    verifyNever(() => gh.isAuthenticated(any()));
  });

  test('availability: notAuthenticated when gh present but not logged in',
      () async {
    when(gh.isAvailable).thenAnswer((_) async => true);
    when(() => gh.isAuthenticated(root)).thenAnswer((_) async => false);
    expect(await service.availability(root), GhAvailability.notAuthenticated);
  });

  test('availability: available when installed + authenticated', () async {
    when(gh.isAvailable).thenAnswer((_) async => true);
    when(() => gh.isAuthenticated(root)).thenAnswer((_) async => true);
    expect(await service.availability(root), GhAvailability.available);
  });

  test('list maps gh state + checks strings to domain enums', () async {
    when(() => gh.listPrs(root)).thenAnswer(
      (_) async => const [
        PullRequestInfo(
          number: 12,
          title: 't',
          state: 'OPEN',
          url: 'https://github.com/o/r/pull/12',
          isDraft: true,
          checks: 'failing',
        ),
      ],
    );
    final prs = await service.list(root);
    expect(prs.single.number, 12);
    expect(prs.single.state, PrState.open);
    expect(prs.single.checks, PrChecks.failing);
    expect(prs.single.isDraft, isTrue);
  });

  test('create pushes BEFORE gh.createPr, and parses the PR number from the '
      'url', () async {
    final pushGate = Completer<void>();
    var pushed = false;
    var createdBeforePush = false;
    when(() => branch.push(root)).thenAnswer((_) async {
      await pushGate.future;
      pushed = true;
    });
    when(
      () => gh.createPr(
        root,
        base: any(named: 'base'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        draft: any(named: 'draft'),
      ),
    ).thenAnswer((_) async {
      if (!pushed) createdBeforePush = true;
      return 'https://github.com/o/r/pull/77';
    });

    final op = service.create(
      root,
      base: 'main',
      title: 't',
      body: 'b',
      draft: false,
    );
    await Future<void>.delayed(Duration.zero);
    pushGate.complete();
    final ref = await op;

    expect(createdBeforePush, isFalse, reason: 'push must finish before create');
    expect(ref.number, 77);
    expect(ref.url, endsWith('/pull/77'));
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `fvm flutter test test/features/collections/data/services/gh_pull_request_service_test.dart`
Expected: FAIL — `GhPullRequestService` undefined.

- [ ] **Step 3: Implement the service**

Create `lib/features/collections/data/services/gh_pull_request_service.dart`:

```dart
import 'package:getman/core/git/gh_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';

/// `gh`-backed [PullRequestService]. Composes [GhService] with the Spec B
/// [BranchService] so the pre-create push reuses the flush-guarded push (no
/// duplicated mirror-race handling — PR creation itself never touches the
/// working tree).
class GhPullRequestService implements PullRequestService {
  GhPullRequestService(this._gh, this._branch);

  final GhService _gh;
  final BranchService _branch;

  @override
  Future<GhAvailability> availability(String root) async {
    if (!await _gh.isAvailable()) return GhAvailability.notInstalled;
    if (!await _gh.isAuthenticated(root)) {
      return GhAvailability.notAuthenticated;
    }
    return GhAvailability.available;
  }

  @override
  Future<List<PullRequestEntity>> list(String root) async {
    final raw = await _gh.listPrs(root);
    return [for (final p in raw) _toEntity(p)];
  }

  @override
  Future<PullRequestRef> create(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  }) async {
    // Ensure the branch (and its latest commits) are on the remote first —
    // gh pr create would otherwise prompt for a remote on stdin, which a
    // non-interactive Process.run cannot answer. push sets upstream on the
    // first push.
    await _branch.push(root);
    final url = await _gh.createPr(
      root,
      base: base,
      title: title,
      body: body,
      draft: draft,
    );
    return PullRequestRef(number: _numberFromUrl(url), url: url);
  }

  @override
  Future<String?> defaultBase(String root) => _gh.defaultBranch(root);

  PullRequestEntity _toEntity(PullRequestInfo p) => PullRequestEntity(
    number: p.number,
    title: p.title,
    state: switch (p.state) {
      'MERGED' => PrState.merged,
      'CLOSED' => PrState.closed,
      _ => PrState.open,
    },
    url: p.url,
    isDraft: p.isDraft,
    checks: switch (p.checks) {
      'pending' => PrChecks.pending,
      'passing' => PrChecks.passing,
      'failing' => PrChecks.failing,
      _ => PrChecks.none,
    },
  );

  int _numberFromUrl(String url) {
    final last = url.split('/').where((s) => s.isNotEmpty).lastOrNull;
    return int.tryParse(last ?? '') ?? 0;
  }
}
```

- [ ] **Step 4: Run, verify green**

Run: `fvm flutter test test/features/collections/data/services/gh_pull_request_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Register in DI**

In `lib/core/di/injection_container.dart`, near the `BranchService` /
`ReviewService` registrations, add (with sorted imports):

```dart
import 'package:getman/core/git/gh_service.dart';
import 'package:getman/features/collections/data/services/gh_pull_request_service.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';
```

```dart
  sl.registerLazySingleton<GhService>(createGhService);
  sl.registerLazySingleton<PullRequestService>(
    () => GhPullRequestService(sl(), sl()),
  );
```

- [ ] **Step 6: Gate + commit**

```bash
fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint
git add lib/features/collections/data/services/gh_pull_request_service.dart \
        lib/core/di/injection_container.dart \
        test/features/collections/data/services/gh_pull_request_service_test.dart
git commit -m "feat(collections): GhPullRequestService (push-then-create) + DI"
```

---

## Task 6: PullRequestsBloc

**Files:**
- Create: `lib/features/collections/presentation/bloc/pull_requests_bloc.dart` / `pull_requests_event.dart` / `pull_requests_state.dart`
- Modify: `lib/core/di/injection_container.dart` (register the bloc)
- Test: `test/features/collections/presentation/bloc/pull_requests_bloc_test.dart`

**Interfaces:**
- Consumes: `PullRequestService`, entities (Task 4).
- Produces: `PullRequestsBloc(service: PullRequestService)`; events
  `LoadPullRequests(root)`, `CreatePullRequest(root, base, title, body, draft)`
  (Equatable, all fields in props); state
  `PullRequestsState {PrStatus status, GhAvailability availability, List<PullRequestEntity> prs, String? errorMessage, PullRequestRef? lastCreated}` with enum `PrStatus { loading, ready, creating, error }` and `isBusy => status == loading || status == creating`.

- [ ] **Step 1: Write the state + events**

Create `lib/features/collections/presentation/bloc/pull_requests_state.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';

enum PrStatus { loading, ready, creating, error }

class PullRequestsState extends Equatable {
  const PullRequestsState({
    this.status = PrStatus.loading,
    this.availability = GhAvailability.available,
    this.prs = const [],
    this.errorMessage,
    this.lastCreated,
  });

  final PrStatus status;
  final GhAvailability availability;
  final List<PullRequestEntity> prs;
  final String? errorMessage;
  final PullRequestRef? lastCreated;

  bool get isBusy => status == PrStatus.loading || status == PrStatus.creating;

  PullRequestsState copyWith({
    PrStatus? status,
    GhAvailability? availability,
    List<PullRequestEntity>? prs,
    String? errorMessage,
    PullRequestRef? lastCreated,
  }) {
    final next = status ?? this.status;
    return PullRequestsState(
      status: next,
      availability: availability ?? this.availability,
      prs: prs ?? this.prs,
      // Only an error state keeps a message; anything else clears it.
      errorMessage: next == PrStatus.error
          ? (errorMessage ?? this.errorMessage)
          : null,
      lastCreated: lastCreated ?? this.lastCreated,
    );
  }

  @override
  List<Object?> get props => [
    status,
    availability,
    prs,
    errorMessage,
    lastCreated,
  ];
}
```

Create `lib/features/collections/presentation/bloc/pull_requests_event.dart`:

```dart
import 'package:equatable/equatable.dart';

abstract class PullRequestsEvent extends Equatable {
  const PullRequestsEvent();

  @override
  List<Object?> get props => [];
}

/// Check availability, then (if ready) load open PRs for [root].
class LoadPullRequests extends PullRequestsEvent {
  const LoadPullRequests(this.root);
  final String root;

  @override
  List<Object?> get props => [root];
}

class CreatePullRequest extends PullRequestsEvent {
  const CreatePullRequest(
    this.root, {
    required this.base,
    required this.title,
    required this.body,
    required this.draft,
  });

  final String root;
  final String base;
  final String title;
  final String body;
  final bool draft;

  @override
  List<Object?> get props => [root, base, title, body, draft];
}
```

- [ ] **Step 2: Write the failing bloc tests**

Create
`test/features/collections/presentation/bloc/pull_requests_bloc_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements PullRequestService {}

void main() {
  const root = '/ws';
  late _MockService service;

  setUp(() => service = _MockService());

  blocTest<PullRequestsBloc, PullRequestsState>(
    'LoadPullRequests: available → loads PRs',
    build: () {
      when(() => service.availability(root))
          .thenAnswer((_) async => GhAvailability.available);
      when(() => service.list(root)).thenAnswer(
        (_) async => const [
          PullRequestEntity(
            number: 1,
            title: 't',
            state: PrState.open,
            url: 'u',
            isDraft: false,
            checks: PrChecks.passing,
          ),
        ],
      );
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(const LoadPullRequests(root)),
    expect: () => [
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.loading),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.ready)
          .having((s) => s.availability, 'availability',
              GhAvailability.available)
          .having((s) => s.prs.length, 'prs', 1),
    ],
  );

  blocTest<PullRequestsBloc, PullRequestsState>(
    'LoadPullRequests: notInstalled → ready with availability, no list call',
    build: () {
      when(() => service.availability(root))
          .thenAnswer((_) async => GhAvailability.notInstalled);
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(const LoadPullRequests(root)),
    expect: () => [
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.loading),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.ready)
          .having((s) => s.availability, 'availability',
              GhAvailability.notInstalled),
    ],
    verify: (_) => verifyNever(() => service.list(any())),
  );

  blocTest<PullRequestsBloc, PullRequestsState>(
    'CreatePullRequest: creates, then reloads the list',
    build: () {
      when(() => service.availability(root))
          .thenAnswer((_) async => GhAvailability.available);
      when(
        () => service.create(
          root,
          base: any(named: 'base'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer(
        (_) async => const PullRequestRef(number: 9, url: 'u/pull/9'),
      );
      when(() => service.list(root)).thenAnswer((_) async => const []);
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(
      const CreatePullRequest(
        root,
        base: 'main',
        title: 't',
        body: 'b',
        draft: false,
      ),
    ),
    expect: () => [
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.creating),
      isA<PullRequestsState>()
          .having((s) => s.lastCreated?.number, 'lastCreated', 9)
          .having((s) => s.status, 'status', PrStatus.ready),
    ],
    verify: (_) {
      verify(() => service.create(root,
          base: 'main', title: 't', body: 'b', draft: false)).called(1);
      verify(() => service.list(root)).called(1);
    },
  );

  blocTest<PullRequestsBloc, PullRequestsState>(
    'a service failure surfaces as an error state',
    build: () {
      when(() => service.availability(root))
          .thenAnswer((_) async => GhAvailability.available);
      when(() => service.list(root)).thenThrow(Exception('boom'));
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(const LoadPullRequests(root)),
    expect: () => [
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.loading),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', isNotNull),
    ],
  );
}
```

- [ ] **Step 3: Run, verify fail**

Run: `fvm flutter test test/features/collections/presentation/bloc/pull_requests_bloc_test.dart`
Expected: FAIL — `PullRequestsBloc` undefined.

- [ ] **Step 4: Implement the bloc**

Create `lib/features/collections/presentation/bloc/pull_requests_bloc.dart`:

```dart
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';

class PullRequestsBloc extends Bloc<PullRequestsEvent, PullRequestsState> {
  PullRequestsBloc({required PullRequestService service})
    : _service = service,
      super(const PullRequestsState()) {
    on<LoadPullRequests>(_onLoad);
    on<CreatePullRequest>(_onCreate);
  }

  final PullRequestService _service;

  Future<void> _onLoad(
    LoadPullRequests event,
    Emitter<PullRequestsState> emit,
  ) async {
    if (_dropWhileBusy('LoadPullRequests')) return;
    emit(state.copyWith(status: PrStatus.loading));
    try {
      final availability = await _service.availability(event.root);
      if (availability != GhAvailability.available) {
        emit(
          state.copyWith(
            status: PrStatus.ready,
            availability: availability,
            prs: const [],
          ),
        );
        return;
      }
      final prs = await _service.list(event.root);
      emit(
        state.copyWith(
          status: PrStatus.ready,
          availability: availability,
          prs: prs,
        ),
      );
    } on Object catch (e) {
      _fail(emit, e);
    }
  }

  Future<void> _onCreate(
    CreatePullRequest event,
    Emitter<PullRequestsState> emit,
  ) async {
    if (_dropWhileBusy('CreatePullRequest')) return;
    emit(state.copyWith(status: PrStatus.creating));
    try {
      final ref = await _service.create(
        event.root,
        base: event.base,
        title: event.title,
        body: event.body,
        draft: event.draft,
      );
      final prs = await _service.list(event.root);
      emit(
        state.copyWith(
          status: PrStatus.ready,
          prs: prs,
          lastCreated: ref,
        ),
      );
    } on Object catch (e) {
      _fail(emit, e);
    }
  }

  /// Drops a second op while one is running: a concurrent gh call could race
  /// the push/create. Every handler always emits a terminal state, so busy is
  /// always exited — this cannot deadlock.
  bool _dropWhileBusy(String event) {
    if (state.isBusy) {
      log('dropping $event while busy', name: 'PullRequestsBloc');
      return true;
    }
    return false;
  }

  void _fail(Emitter<PullRequestsState> emit, Object error) {
    log('pull-request op failed: $error', name: 'PullRequestsBloc');
    emit(
      state.copyWith(status: PrStatus.error, errorMessage: error.toString()),
    );
  }
}
```

- [ ] **Step 5: Run, verify green**

Run: `fvm flutter test test/features/collections/presentation/bloc/pull_requests_bloc_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Register the bloc in DI**

In `lib/core/di/injection_container.dart`, near the `GitSyncBloc` registration:

```dart
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
```

```dart
  sl.registerFactory(() => PullRequestsBloc(service: sl()));
```

- [ ] **Step 7: Gate + commit**

```bash
fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib < /dev/null
git add lib/features/collections/presentation/bloc/pull_requests_bloc.dart \
        lib/features/collections/presentation/bloc/pull_requests_event.dart \
        lib/features/collections/presentation/bloc/pull_requests_state.dart \
        lib/core/di/injection_container.dart \
        test/features/collections/presentation/bloc/pull_requests_bloc_test.dart
git commit -m "feat(collections): PullRequestsBloc over the service abstraction"
```

---

## Task 7: PullRequestsDialog + branch-chip menu wiring

**Files:**
- Create: `lib/features/collections/presentation/widgets/pull_requests_dialog.dart`
- Create: `lib/core/utils/open_url.dart` (url_launcher wrapper — code below)
- Modify: `lib/features/collections/presentation/widgets/branch_chip.dart`
- Modify: `lib/main.dart` (provide `PullRequestsBloc`)
- Test: `test/features/collections/presentation/widgets/pull_requests_dialog_test.dart`

**Interfaces:**
- Consumes: `PullRequestsBloc`, its state/events (Task 6); the branch chip's existing menu.
- Produces: `PullRequestsDialog.show(BuildContext context, {required String root})`.

Behaviour: on open, dispatch `LoadPullRequests(root)`. Render one of:
**notInstalled** → message `GitHub CLI (gh) not found` + `INSTALL GH` button
opening `https://cli.github.com` in the browser; **notAuthenticated** →
`Sign in with the GitHub CLI` + a hint to run `gh auth login`; **available** →
a `REFRESH` button, `CREATE PULL REQUEST…`, and the list (`No open pull
requests.` when empty). Each PR row shows `#<n>`, title, a draft tag if draft,
a state dot, a checks glyph (`context.appPalette` for colours — reuse
`statusColor`/`colorScheme` tones, never `Colors.*`), and opens its url via the
browser on tap. `CREATE PULL REQUEST…` opens a form (base picker defaulting to
`service.defaultBase`, `PR TITLE`, `PR body (optional)`, `Create as draft`
toggle) that dispatches `CreatePullRequest`. A `PrStatus.error` shows a
`GIT ERROR`-style dialog. After a create that pushed, nudge the chip: dispatch
`LoadBranchStatus(root)` on `GitSyncBloc` (read from context — both blocs are in
scope under the collections header).

**URL opening:** the repo already depends on `url_launcher` (see
`lib/features/tabs/presentation/widgets/response/viewers/html_open_external_io.dart`).
Add a small cross-platform helper `lib/core/utils/open_url.dart` — no `dart:io`,
so no `*_io.dart` gate (`url_launcher` is cross-platform):

```dart
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser. Returns false (never throws) when the
/// url is malformed or no handler is available — callers show a snackbar.
Future<bool> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}
```

- [ ] **Step 1: Write the dialog widget tests**

Create
`test/features/collections/presentation/widgets/pull_requests_dialog_test.dart`
with, at minimum, these `testWidgets` (blocs built INSIDE each body; theme
provided):

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';
import 'package:getman/features/collections/presentation/widgets/pull_requests_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _MockBloc extends MockBloc<PullRequestsEvent, PullRequestsState>
    implements PullRequestsBloc {}

void main() {
  const root = '/ws';

  Widget host(_MockBloc bloc) => MaterialApp(
    theme: brutalistTheme(Brightness.light),
    home: Scaffold(
      body: BlocProvider<PullRequestsBloc>.value(
        value: bloc,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => PullRequestsDialog.show(context, root: root),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('notInstalled shows the install prompt', (tester) async {
    final bloc = _MockBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
        availability: GhAvailability.notInstalled,
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('gh'), findsWidgets);
    expect(find.text('INSTALL GH'), findsOneWidget);
  });

  testWidgets('a ready list renders a PR row', (tester) async {
    final bloc = _MockBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
        availability: GhAvailability.available,
        prs: [
          PullRequestEntity(
            number: 42,
            title: 'feat: thing',
            state: PrState.open,
            url: 'https://github.com/o/r/pull/42',
            isDraft: false,
            checks: PrChecks.passing,
          ),
        ],
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('42'), findsWidgets);
    expect(find.text('feat: thing'), findsOneWidget);
    expect(find.text('CREATE PULL REQUEST…'), findsOneWidget);
  });

  testWidgets('empty ready list shows the empty message', (tester) async {
    final bloc = _MockBloc();
    when(() => bloc.state).thenReturn(
      const PullRequestsState(
        status: PrStatus.ready,
        availability: GhAvailability.available,
      ),
    );
    await tester.pumpWidget(host(bloc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('No open pull requests.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `fvm flutter test test/features/collections/presentation/widgets/pull_requests_dialog_test.dart`
Expected: FAIL — `PullRequestsDialog` undefined.

- [ ] **Step 3: Implement the dialog**

Create `lib/features/collections/presentation/widgets/pull_requests_dialog.dart`.
Structure (read theme tokens via `context.appLayout` / `context.appTypography` /
`context.appPalette`; no hardcoded sizes/colours; wrap async dialog/browser
calls in `unawaited`; capture the bloc before any async gap):

- `static Future<void> show(BuildContext, {required String root})` →
  `showDialog` wrapping a `ResponsiveDialog` whose body is a
  `BlocConsumer<PullRequestsBloc, PullRequestsState>` (listener routes
  `PrStatus.error` → a `GIT ERROR` AlertDialog like `branch_chip.dart` does;
  builder switches on `state.availability` / `state.status`). Dispatch
  `LoadPullRequests(root)` from a `StatefulWidget` `initState` (so it fires once
  on open), mirroring `review_changes_button.dart`.
- **notInstalled** view: a column with the `GitHub CLI (gh) not found` text and
  an `INSTALL GH` button that opens `https://cli.github.com` (via the URL
  helper — see the implementer note above).
- **notAuthenticated** view: `Sign in with the GitHub CLI` + `Run: gh auth
  login` hint text, plus a `REFRESH` button dispatching `LoadPullRequests`.
- **available** view: a header `Row` with `REFRESH` and `CREATE PULL REQUEST…`,
  then the list (`ListView` of PR rows or `No open pull requests.`). Each row:
  `#<number>` + title + optional `DRAFT` tag + a state/checks indicator, tapping
  opens `pr.url`. Disable `REFRESH`/`CREATE` while `state.isBusy`.
- **create form:** a second `showDialog` (`_CreatePrForm`) with a base
  `DropdownButton` (seeded from `LoadBranchStatus`/`GitSyncBloc` branches or a
  fetched `defaultBase`; simplest v1: a `TextFormField` prefilled with the
  default base string), a `PR TITLE` field (prefill from the branch's last
  commit is optional — leave blank is fine), a `PR body (optional)` field, and a
  `Create as draft` `SwitchListTile`. `CREATE` dispatches
  `CreatePullRequest(root, base:…, title:…, body:…, draft:…)` on the captured
  bloc, then pops. After the create resolves (`lastCreated` changes), the outer
  listener shows a snackbar `PR #<n> opened` with an `OPEN IN BROWSER` action,
  and nudges the chip by `context.read<GitSyncBloc>().add(LoadBranchStatus(root))`.

Keep the widget focused; extract `_PrRow`, `_InstallPrompt`, `_AuthPrompt`,
`_CreatePrForm` as private widgets in the same file.

- [ ] **Step 4: Wire the branch-chip menu item**

In `lib/features/collections/presentation/widgets/branch_chip.dart`, add a
`PopupMenuItem<String>` with `value: 'prs'` and child `Text('PULL REQUESTS…')`
after the `stashes` item, and in `_onSelected` add:

```dart
      case 'prs':
        unawaited(PullRequestsDialog.show(context, root: root));
```

Add the import
`import 'package:getman/features/collections/presentation/widgets/pull_requests_dialog.dart';`
and `import 'dart:async';` (for `unawaited`) if not present.

- [ ] **Step 5: Provide the bloc in main.dart**

In `lib/main.dart`, add to the `MultiBlocProvider` (near `GitSyncBloc`):

```dart
        BlocProvider(create: (_) => di.sl<PullRequestsBloc>()),
```

with the import. (The dialog is opened from the chip, which lives under this
provider — so `context.read<PullRequestsBloc>()` resolves.)

- [ ] **Step 6: Run the dialog tests + the collections/home suites**

Run: `fvm flutter test test/features/collections test/features/home`
Expected: PASS. If any collections/side-menu host that builds the header now
needs a `PullRequestsBloc` provider, add a `MockPullRequestsBloc` exactly as the
`GitSyncBloc`/`ReviewBloc` providers were added — but note the chip only reads
`PullRequestsBloc` when the menu item is tapped, so a host that never taps
`PULL REQUESTS…` and uses a null workspace path will not need it (verify).

- [ ] **Step 7: Gate + commit**

```bash
fvm dart format lib test && fvm flutter analyze && fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib < /dev/null
git add lib/features/collections/presentation/widgets/pull_requests_dialog.dart \
        lib/features/collections/presentation/widgets/branch_chip.dart \
        lib/main.dart \
        test/features/collections/presentation/widgets/pull_requests_dialog_test.dart
git commit -m "feat(git): pull requests dialog + branch-chip menu entry"
```

---

## Task 8: Full gate + wiki

**Files:**
- Modify: `docs/superpowers/plans/2026-07-14-git-pr-integration.md` (tick boxes)
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

Expected: **0 issues from every pass and 100% green tests.** These are separate
processes — a clean `flutter analyze` does not imply custom_lint or bloc_lint.

- [ ] **Step 2: Update the wiki**

Clone `https://github.com/thiagomiranda3/Getman.wiki.git` (push over SSH:
`git remote set-url origin git@github.com:thiagomiranda3/Getman.wiki.git`).
Add a **Pull requests** section to `Version-Control.md`, with verbatim UI labels:

- Reached from the branch chip → **PULL REQUESTS…**.
- Uses the **GitHub CLI (`gh`)** — install it (link `cli.github.com`) and run
  `gh auth login`; **Getman stores no credentials.**
- The dialog lists **open** PRs with state + checks; a row opens it in the
  browser; **REFRESH** re-reads.
- **CREATE PULL REQUEST…**: base branch, **PR TITLE**, body, **Create as draft**.
  Creating pushes the branch first (setting upstream), then opens the PR.
- Desktop-only; requires `git` and `gh` on your PATH.

Commit and push (default branch `master`).

- [ ] **Step 3: Commit the ticked plan**

```bash
git add docs/superpowers/plans/2026-07-14-git-pr-integration.md
git commit -m "docs(git): tick off the Spec C implementation plan"
```

---

## Self-Review Notes

- **Spec coverage:** create PRs (Tasks 3,5,7) · list open PRs + state + checks
  (Tasks 2,5,7) · gh transport, no creds (Tasks 1–3) · push-then-create (Task 5)
  · gh-missing install prompt + gh-unauth prompt (Tasks 5,7) · branch-chip entry
  (Task 7) · draft toggle (Tasks 3,7) · web-gating (stub Task 1, kIsWeb inherited
  via the chip's own gate) · wiki (Task 8).
- **Ordering:** Task 7 uses `PullRequestsDialog`; the chip edit is in the same
  task, so no cross-task compile gap. Task 5 depends on Spec B's
  `BranchService.push`.
- **Naming consistency:** core `PullRequestInfo{number,title,state:String,url,
  isDraft,checks:String}` → domain `PullRequestEntity{…,state:PrState,
  checks:PrChecks}` via `GhPullRequestService._toEntity`; `createPr`→`String`
  (url) → domain `PullRequestRef{number,url}`; enums `PrState`/`PrChecks`/
  `GhAvailability`/`PrStatus` each defined once.
- **Non-vacuity reminder:** the push-then-create ordering test (Task 5) uses a
  Completer gate, not a bare `thenAnswer((_) async {})` — the Spec B lesson that
  a sync-until-first-await stub satisfies `verifyInOrder` vacuously.

# Static-Analysis Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend Getman's static-analysis stack with four project-local architecture lints, three cherry-picked complexity metrics, two re-enabled core lints, dead-code/unused-file detection, and dependency-vulnerability + update tooling — all hard-gated in CI.

**Architecture:** New `custom_lint` rules live in the existing `tools/getman_lints/` package and run in the existing `dart run custom_lint` pass. Complexity metrics ride that same pass via `solid_lints`. Unused-code/files run as an external DCM CLI step in CI. Supply-chain checks (OSV-Scanner, Dependabot) are GitHub-native. A new `tools/getman_lints/example/` fixtures package gives the lint rules `// expect_lint:`-based tests (none exist today).

**Tech Stack:** Dart `analyzer` 8.4 + `custom_lint_builder` 0.8 (lint rules), `solid_lints` (metrics), DCM standalone CLI (unused code/files), `google/osv-scanner-action` + Dependabot (supply chain).

## Global Constraints

- Flutter is pinned via `.fvmrc` — invoke as `fvm flutter …` / `fvm dart …`, never plain.
- Analyzer toolchain is pinned to **8.4** — do **not** bump `analyzer`/`custom_lint`/`bloc_lint` past their current constraints.
- Imports are `package:getman/…` everywhere (no relative imports) in app code.
- Done-bar (must ALL be green before any task is "done"): `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0 issues), `fvm dart run bloc_tools:bloc lint lib` (0 issues), `fvm dart format` clean, `fvm flutter test` 100% green.
- New `custom_lint` rules use `ErrorSeverity.WARNING` (matching the two existing rules); `custom_lint` fails the pass on any finding regardless of severity.
- Rollout is **hard-gate now**: each new check must end green against the current codebase (fix or `// ignore`-with-reason every surfaced violation in-task).
- Suppress a justified exception with a per-line `// ignore: <rule>` + a one-line reason.
- Pre-measured baseline (2026-06-26): A1/A2/A3 and both G lints already report **0** violations on `lib/`.

---

### Task 1: Establish the lint-rule test harness (fixtures package)

Build a minimal sub-package whose only job is to host fixture files that custom_lint
checks via `// expect_lint:` comments. Prove it works against an **existing** rule
before adding new ones.

**Files:**
- Create: `tools/getman_lints/example/pubspec.yaml`
- Create: `tools/getman_lints/example/analysis_options.yaml`
- Create: `tools/getman_lints/example/lib/existing_rules_fixture.dart`

**Interfaces:**
- Consumes: the existing `getman_lints` plugin (`avoid_hardcoded_brand_colors`).
- Produces: the test command `cd tools/getman_lints/example && fvm dart run custom_lint` (exit 0 = all `expect_lint` expectations satisfied). Later tasks add fixture files here.

- [ ] **Step 1: Create the fixtures package pubspec**

`tools/getman_lints/example/pubspec.yaml`:
```yaml
name: getman_lints_example
description: >-
  Fixture package for getman_lints. Hosts files annotated with
  `// expect_lint:` comments so custom_lint can verify each project-local rule
  fires exactly where expected. Not published; not part of the app.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.4

dev_dependencies:
  custom_lint: ^0.8.0
  getman_lints:
    path: ../
```

- [ ] **Step 2: Enable the plugin for fixtures**

`tools/getman_lints/example/analysis_options.yaml`:
```yaml
analyzer:
  plugins:
    - custom_lint
```

- [ ] **Step 3: Write a fixture that pins an EXISTING rule (this is the failing test)**

`tools/getman_lints/example/lib/existing_rules_fixture.dart`:
```dart
// Fixtures for getman_lints. Imports are intentionally unresolved — every rule
// matches on file path + raw import URI + syntax, never on resolved elements,
// so these files need no real dependencies. The analyzer's own
// "uri_does_not_exist" is not a custom_lint lint and does not affect expect_lint.
// ignore_for_file: uri_does_not_exist, unused_import, unused_local_variable

import 'package:flutter/material.dart';

void brandColorIsFlagged() {
  // expect_lint: avoid_hardcoded_brand_colors
  final c = Colors.red;
}
```

- [ ] **Step 4: Resolve deps and run — verify the harness reports SUCCESS**

Run:
```bash
cd tools/getman_lints/example && fvm dart pub get && fvm dart run custom_lint
```
Expected: `No issues found!` — meaning the `expect_lint` on `Colors.red` matched a
real `avoid_hardcoded_brand_colors` lint (an unsatisfied expectation would print an
error). If it instead reports an unfulfilled-expectation error, the harness is
mis-wired — fix before proceeding.

- [ ] **Step 5: Commit**

```bash
git add tools/getman_lints/example
git commit -m "test(lints): add expect_lint fixtures harness for getman_lints

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 2: Rule A1 — `domain_no_infrastructure_imports`

A file whose path contains `/domain/` must not import Flutter, `dart:io`/`dart:ui`,
`dio`, `hive`, or any feature's `data/` layer.

**Files:**
- Modify: `tools/getman_lints/lib/getman_lints.dart` (add rule class + register it)
- Create (fixtures): `tools/getman_lints/example/lib/domain_imports_fixture.dart`

**Interfaces:**
- Consumes: `custom_lint_builder` (`DartLintRule`, `context.registry.addImportDirective`), the existing `_posix(String)` helper in `getman_lints.dart`.
- Produces: lint name `domain_no_infrastructure_imports`.

- [ ] **Step 1: Write the failing fixture**

`tools/getman_lints/example/lib/domain_imports_fixture.dart`:
```dart
// ignore_for_file: uri_does_not_exist, unused_import

// This file's path does NOT contain /domain/, so these must NOT be flagged:
import 'package:flutter/material.dart';
import 'package:getman/features/x/data/foo.dart';
```

And a positive-case fixture under a `/domain/` path —
`tools/getman_lints/example/lib/feature/domain/domain_bad_fixture.dart`:
```dart
// ignore_for_file: uri_does_not_exist, unused_import

// expect_lint: domain_no_infrastructure_imports
import 'package:flutter/material.dart';
// expect_lint: domain_no_infrastructure_imports
import 'dart:io';
// expect_lint: domain_no_infrastructure_imports
import 'package:dio/dio.dart';
// expect_lint: domain_no_infrastructure_imports
import 'package:hive_ce/hive.dart';
// expect_lint: domain_no_infrastructure_imports
import 'package:getman/features/x/data/foo_model.dart';

// Allowed in domain — must NOT be flagged:
import 'package:equatable/equatable.dart';
import 'package:getman/features/x/domain/bar.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: FAIL — unfulfilled `expect_lint: domain_no_infrastructure_imports` (rule doesn't exist yet).

- [ ] **Step 3: Implement the rule**

In `tools/getman_lints/lib/getman_lints.dart`, register it in `getLintRules`:
```dart
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
    AvoidGetItInWidgets(),
    AvoidHardcodedBrandColors(),
    DomainNoInfrastructureImports(),
  ];
```
And add the class:
```dart
/// Enforces "domain layer has zero imports from data/ or Flutter UI" (CLAUDE.md
/// §2): a file under any `domain/` directory may import only pure Dart +
/// equatable — never Flutter, dart:io/dart:ui, dio, hive, or a feature's data/.
class DomainNoInfrastructureImports extends DartLintRule {
  const DomainNoInfrastructureImports() : super(code: _code);

  static const _code = LintCode(
    name: 'domain_no_infrastructure_imports',
    problemMessage:
        'The domain layer must be pure Dart + equatable. Do not import Flutter, '
        'dart:io/dart:ui, dio, hive, or a feature data/ layer from domain/ '
        '(CLAUDE.md §2).',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final path = _posix(resolver.path);
    if (!path.contains('/lib/') || !path.contains('/domain/')) return;

    context.registry.addImportDirective((node) {
      final uri = node.uri.stringValue;
      if (uri == null) return;
      final banned =
          uri == 'dart:io' ||
          uri == 'dart:ui' ||
          uri.startsWith('package:flutter/') ||
          uri.startsWith('package:dio/') ||
          uri.startsWith('package:hive') ||
          (uri.startsWith('package:getman/') && uri.contains('/data/'));
      if (banned) reporter.atNode(node, _code);
    });
  }
}
```

- [ ] **Step 4: Run to verify the fixture passes**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: `No issues found!`

- [ ] **Step 5: Verify the real app is still clean against the new rule**

Run (repo root): `fvm dart run custom_lint`
Expected: `No issues found!` (baseline confirmed 0 domain-boundary violations).

- [ ] **Step 6: Commit**

```bash
git add tools/getman_lints/lib/getman_lints.dart tools/getman_lints/example/lib
git commit -m "feat(lints): add domain_no_infrastructure_imports rule

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 3: Rule A2 — `bloc_depends_on_abstractions`

A `*_bloc.dart` / `*_cubit.dart` file must not import a `data/` layer, `dio`, or `hive`.

**Files:**
- Modify: `tools/getman_lints/lib/getman_lints.dart`
- Create (fixtures): `tools/getman_lints/example/lib/sample_bloc.dart`, `tools/getman_lints/example/lib/sample_widget.dart`

**Interfaces:**
- Produces: lint name `bloc_depends_on_abstractions`.

- [ ] **Step 1: Write the failing fixtures**

`tools/getman_lints/example/lib/sample_bloc.dart`:
```dart
// ignore_for_file: uri_does_not_exist, unused_import

// expect_lint: bloc_depends_on_abstractions
import 'package:getman/features/x/data/x_repository_impl.dart';
// expect_lint: bloc_depends_on_abstractions
import 'package:dio/dio.dart';
// expect_lint: bloc_depends_on_abstractions
import 'package:hive_ce/hive.dart';

// Allowed — abstract domain repo:
import 'package:getman/features/x/domain/repositories/x_repository.dart';
```

`tools/getman_lints/example/lib/sample_widget.dart` (NOT a bloc file — must NOT flag):
```dart
// ignore_for_file: uri_does_not_exist, unused_import
import 'package:getman/features/x/data/x_repository_impl.dart';
import 'package:dio/dio.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: FAIL — unfulfilled `expect_lint: bloc_depends_on_abstractions`.

- [ ] **Step 3: Implement the rule**

Register `BlocDependsOnAbstractions()` in `getLintRules`, then add:
```dart
/// Enforces "BLoCs depend on abstract Repository types, never ...Impl/Hive/Dio
/// directly" (CLAUDE.md §2/§7): a `*_bloc.dart` / `*_cubit.dart` file may not
/// import a data/ layer, dio, or hive. Detection is by import directory/package,
/// not an `Impl` name heuristic.
class BlocDependsOnAbstractions extends DartLintRule {
  const BlocDependsOnAbstractions() : super(code: _code);

  static const _code = LintCode(
    name: 'bloc_depends_on_abstractions',
    problemMessage:
        'BLoCs/Cubits must depend on abstract Repository types. Do not import a '
        'data/ layer, dio, or hive directly from a bloc/cubit (CLAUDE.md §2/§7).',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final path = _posix(resolver.path);
    if (!path.contains('/lib/')) return;
    if (!path.endsWith('_bloc.dart') && !path.endsWith('_cubit.dart')) return;

    context.registry.addImportDirective((node) {
      final uri = node.uri.stringValue;
      if (uri == null) return;
      final banned =
          uri.startsWith('package:dio/') ||
          uri.startsWith('package:hive') ||
          (uri.startsWith('package:getman/') && uri.contains('/data/'));
      if (banned) reporter.atNode(node, _code);
    });
  }
}
```

- [ ] **Step 4: Run to verify the fixtures pass**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: `No issues found!`

- [ ] **Step 5: Verify the real app is clean**

Run (repo root): `fvm dart run custom_lint`
Expected: `No issues found!` (8 bloc/cubit files, baseline 0 violations).

- [ ] **Step 6: Commit**

```bash
git add tools/getman_lints/lib/getman_lints.dart tools/getman_lints/example/lib
git commit -m "feat(lints): add bloc_depends_on_abstractions rule

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 4: Rule A3 — `platform_io_outside_io_files`

`dart:io`, `updat`, `path_provider`, `package_info_plus` may only be imported from
`*_io.dart` files (the conditional-import native-side convention; protects web builds).

**Files:**
- Modify: `tools/getman_lints/lib/getman_lints.dart`
- Create (fixtures): `tools/getman_lints/example/lib/platform_bad_fixture.dart`, `tools/getman_lints/example/lib/platform_ok_io.dart`

**Interfaces:**
- Produces: lint name `platform_io_outside_io_files`.

- [ ] **Step 1: Write the failing fixtures**

`tools/getman_lints/example/lib/platform_bad_fixture.dart` (not `_io.dart` → flag):
```dart
// ignore_for_file: uri_does_not_exist, unused_import

// expect_lint: platform_io_outside_io_files
import 'dart:io';
// expect_lint: platform_io_outside_io_files
import 'package:updat/updat.dart';
// expect_lint: platform_io_outside_io_files
import 'package:path_provider/path_provider.dart';
// expect_lint: platform_io_outside_io_files
import 'package:package_info_plus/package_info_plus.dart';
```

`tools/getman_lints/example/lib/platform_ok_io.dart` (`_io.dart` → allowed):
```dart
// ignore_for_file: uri_does_not_exist, unused_import
import 'dart:io';
import 'package:path_provider/path_provider.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: FAIL — unfulfilled `expect_lint: platform_io_outside_io_files`.

- [ ] **Step 3: Implement the rule**

Register `PlatformIoOutsideIoFiles()` in `getLintRules`, then add:
```dart
/// Enforces web-safety (CLAUDE.md §1): dart:io / updat / path_provider /
/// package_info_plus may only be imported from `*_io.dart` files (the
/// conditional-import native-side convention). Keeps web builds clean.
class PlatformIoOutsideIoFiles extends DartLintRule {
  const PlatformIoOutsideIoFiles() : super(code: _code);

  static const _code = LintCode(
    name: 'platform_io_outside_io_files',
    problemMessage:
        'dart:io / updat / path_provider / package_info_plus may only be '
        'imported from a *_io.dart file (conditional-import native side). Move '
        'native code behind an *_io.dart + stub split to keep web builds clean '
        '(CLAUDE.md §1).',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final path = _posix(resolver.path);
    if (!path.contains('/lib/') || path.endsWith('_io.dart')) return;

    context.registry.addImportDirective((node) {
      final uri = node.uri.stringValue;
      if (uri == null) return;
      final banned =
          uri == 'dart:io' ||
          uri.startsWith('package:updat/') ||
          uri.startsWith('package:path_provider/') ||
          uri.startsWith('package:package_info_plus/');
      if (banned) reporter.atNode(node, _code);
    });
  }
}
```

- [ ] **Step 4: Run to verify the fixtures pass**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: `No issues found!`

- [ ] **Step 5: Verify the real app is clean**

Run (repo root): `fvm dart run custom_lint`
Expected: `No issues found!` (all 9 platform-import sites are `*_io.dart`).

- [ ] **Step 6: Commit**

```bash
git add tools/getman_lints/lib/getman_lints.dart tools/getman_lints/example/lib
git commit -m "feat(lints): add platform_io_outside_io_files rule

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 5: Rule B — `equatable_props_complete`

For a class that `extends Equatable`, every declared instance field must appear in
the `props` getter's returned list. **Syntactic** detection (superclass name +
parse the `props` list expression) — no element resolution, so it is robust against
the analyzer-8.4 element-model migration. Known limitation (documented in the rule
doc comment): only catches direct `extends Equatable`, not indirect inheritance, and
treats `EquatableMixin` the same when present in the `with` clause.

**Files:**
- Modify: `tools/getman_lints/lib/getman_lints.dart`
- Create (fixtures): `tools/getman_lints/example/lib/equatable_fixture.dart`

**Interfaces:**
- Consumes: `context.registry.addClassDeclaration`, analyzer AST nodes (`ClassDeclaration`, `FieldDeclaration`, `MethodDeclaration`, `ListLiteral`, `SimpleIdentifier`).
- Produces: lint name `equatable_props_complete`.

- [ ] **Step 1: Write the failing fixtures**

`tools/getman_lints/example/lib/equatable_fixture.dart`:
```dart
// ignore_for_file: uri_does_not_exist, unused_import, must_be_immutable
import 'package:equatable/equatable.dart';

// MISSING field `b` in props → the class name is flagged.
// expect_lint: equatable_props_complete
class BadState extends Equatable {
  const BadState(this.a, this.b);
  final int a;
  final int b;
  @override
  List<Object?> get props => [a];
}

// Complete → not flagged.
class GoodState extends Equatable {
  const GoodState(this.a, this.b);
  final int a;
  final int b;
  @override
  List<Object?> get props => [a, b];
}

// Field intentionally excluded with a reason → suppressed, not flagged.
class ExcludedState extends Equatable {
  const ExcludedState(this.a, this.id);
  final int a;
  // id is deliberately outside equality.
  // ignore: equatable_props_complete
  final int id;
  @override
  List<Object?> get props => [a];
}

// Non-Equatable class → never flagged.
class Plain {
  Plain(this.a);
  final int a;
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: FAIL — unfulfilled `expect_lint: equatable_props_complete` on `BadState`.

- [ ] **Step 3: Implement the rule**

Register `EquatablePropsComplete()` in `getLintRules`, then add:
```dart
/// Enforces "Equatable on every state/event" correctness: for a class that
/// `extends Equatable` (or mixes `EquatableMixin`), every declared instance
/// field must appear in the `props` getter. A field omitted from `props` makes
/// distinct values compare equal (states silently fail to rebuild).
///
/// Detection is syntactic: it matches the `extends Equatable` / `with
/// EquatableMixin` clause by name and parses the identifiers in the `props`
/// list literal. Limitation: it does not follow indirect inheritance (a class
/// extending a base that extends Equatable). Deliberately-excluded fields use
/// `// ignore: equatable_props_complete` + a reason.
class EquatablePropsComplete extends DartLintRule {
  const EquatablePropsComplete() : super(code: _code);

  static const _code = LintCode(
    name: 'equatable_props_complete',
    problemMessage:
        'This Equatable class omits one or more instance fields from `props`; '
        'distinct values will compare equal. Add the missing field(s) to props, '
        'or exclude one deliberately with `// ignore: equatable_props_complete`.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (!_posix(resolver.path).contains('/lib/')) return;

    context.registry.addClassDeclaration((node) {
      if (!_isEquatable(node)) return;

      // Collect declared instance field names (skip static + const-less? keep
      // all instance fields; static fields are excluded).
      final fields = <String>{};
      for (final member in node.members) {
        if (member is FieldDeclaration && !member.isStatic) {
          for (final v in member.fields.variables) {
            fields.add(v.name.lexeme);
          }
        }
      }
      if (fields.isEmpty) return;

      // Find the `props` getter and collect simple identifiers in its returned
      // list literal (handles `=> [a, b]` and a block body `{ return [a, b]; }`).
      final propsNames = _propsIdentifiers(node);
      if (propsNames == null) return; // no recognizable props getter

      final missing = fields.difference(propsNames);
      if (missing.isNotEmpty) {
        reporter.atToken(node.name, _code);
      }
    });
  }

  bool _isEquatable(ClassDeclaration node) {
    final ext = node.extendsClause?.superclass.name2.lexeme;
    if (ext == 'Equatable') return true;
    final withClause = node.withClause;
    if (withClause != null) {
      for (final t in withClause.mixinTypes) {
        if (t.name2.lexeme == 'EquatableMixin') return true;
      }
    }
    return false;
  }

  Set<String>? _propsIdentifiers(ClassDeclaration node) {
    for (final member in node.members) {
      if (member is MethodDeclaration &&
          member.isGetter &&
          member.name.lexeme == 'props') {
        final body = member.body;
        ListLiteral? list;
        if (body is ExpressionFunctionBody) {
          final expr = body.expression;
          if (expr is ListLiteral) list = expr;
        } else if (body is BlockFunctionBody) {
          for (final stmt in body.block.statements) {
            if (stmt is ReturnStatement && stmt.expression is ListLiteral) {
              list = stmt.expression! as ListLiteral;
              break;
            }
          }
        }
        if (list == null) return null;
        final names = <String>{};
        for (final element in list.elements) {
          if (element is SimpleIdentifier) names.add(element.name);
          // `...super.props`, method calls, etc. are ignored (can't attribute
          // to a local field name) — they neither add nor remove coverage.
        }
        return names;
      }
    }
    return null;
  }
}
```

Note: if `node.name2`/`name.lexeme`/`atToken` differ under analyzer 8.4, the
fixtures loop in Step 4 will surface the compile/behavior mismatch immediately —
adjust the accessor (e.g. `reporter.atNode(node, _code)` if `atToken` is
unavailable) and re-run.

- [ ] **Step 4: Run to verify the fixtures pass**

Run: `cd tools/getman_lints/example && fvm dart run custom_lint`
Expected: `No issues found!` (BadState flagged-as-expected; GoodState/ExcludedState/Plain clean).

- [ ] **Step 5: Run against the real app and clean up**

Run (repo root): `fvm dart run custom_lint`
Expected: lists any real props-omission across the 49 Equatable files. For each:
either add the missing field to `props`, OR if the omission is deliberate, add
`// ignore: equatable_props_complete` + a one-line reason on the class. Re-run until
`No issues found!`.

- [ ] **Step 6: Run the app test suite (state-equality changes can shift behavior)**

Run: `fvm flutter test`
Expected: 100% green. (Adding a field to `props` changes equality — confirm no test
depended on the buggy equality.)

- [ ] **Step 7: Commit**

```bash
git add tools/getman_lints/lib/getman_lints.dart tools/getman_lints/example/lib lib
git commit -m "feat(lints): add equatable_props_complete rule

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 6: Config lints (G) — re-enable `close_sinks` + add `discarded_futures`

Both measured at 0 violations → pure config, hard-gate is free.

**Files:**
- Modify: `analysis_options.yaml`

**Interfaces:**
- Consumes: nothing. Produces: two newly-active analyzer lints in `fvm flutter analyze`.

- [ ] **Step 1: Add the overrides**

In `analysis_options.yaml`, add an `errors:` block under `analyzer:` and a rule under
`linter.rules:`.

Under `analyzer:` (sibling of `plugins:`):
```yaml
  errors:
    # VGA enables `close_sinks` but pins it to `ignore`; re-promote it so
    # undisposed StreamController/Sink fields are caught (RealtimeService etc.).
    close_sinks: warning
```
Under `linter.rules:` (alongside the existing pinned rules):
```yaml
    # Companion to unawaited_futures (already on): flags fire-and-forget futures
    # in non-async contexts (constructors, void callbacks). Not in VGA.
    discarded_futures: true
```

- [ ] **Step 2: Run the analyzer — verify still clean**

Run: `fvm flutter analyze`
Expected: `No issues found!` (baseline measured 0 for both; if anything surfaces,
fix it, or `unawaited(...)` / `// ignore: <rule>` + reason a deliberate site).

- [ ] **Step 3: Commit**

```bash
git add analysis_options.yaml
git commit -m "chore(analysis): re-enable close_sinks + add discarded_futures

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 7: Metrics (D) — cherry-picked `solid_lints` rules

Enable exactly three pure-metric rules via the existing custom_lint pass. Flip
custom_lint to opt-in mode so `solid_lints`' other rules stay off.

**Files:**
- Modify: `pubspec.yaml` (add `solid_lints` dev_dependency)
- Modify: `analysis_options.yaml` (add `custom_lint:` config block)

**Interfaces:**
- Consumes: `solid_lints` rules `cyclomatic_complexity`, `number_of_parameters`, `function_lines_of_code`; the four `getman_lints` rules + two existing ones.
- Produces: three active metric lints in `fvm dart run custom_lint`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` `dev_dependencies:` add (alphabetical position):
```yaml
  solid_lints: ^0.4.0
```
Run: `fvm flutter pub get`
Expected: resolves. If it forces an analyzer bump past 8.4, STOP — pin to the
highest `solid_lints` that resolves against analyzer 8.4 (try `^0.3.0`) and note the
version chosen.

- [ ] **Step 2: Configure custom_lint to opt-in mode with only the intended rules**

In `analysis_options.yaml`, append a top-level `custom_lint:` block:
```yaml
# custom_lint runs in opt-in mode: only the rules listed here are active. This
# keeps solid_lints scoped to the three pure-metric rules (no VGA overlap) while
# preserving the getman_lints architecture rules.
custom_lint:
  enable_all_lint_rules: false
  rules:
    # getman_lints (project-local architecture rules)
    - avoid_get_it_in_widgets
    - avoid_hardcoded_brand_colors
    - domain_no_infrastructure_imports
    - bloc_depends_on_abstractions
    - platform_io_outside_io_files
    - equatable_props_complete
    # solid_lints — cherry-picked metrics only (thresholds calibrated in Step 4)
    - cyclomatic_complexity:
        max_complexity: 20
    - number_of_parameters:
        max_parameters: 8
    - function_lines_of_code:
        max_lines: 100
```

- [ ] **Step 3: Verify ONLY the intended rules are active**

Run: `fvm dart run custom_lint`
Expected: output references only the rules above. If `solid_lints` rules other than
the three appear (i.e. opt-in mode didn't take), STOP and switch to per-rule
disabling instead, then re-run until only the intended set is active.

- [ ] **Step 4: Calibrate thresholds against the real codebase, then fix outliers**

With the generous starting thresholds (20/8/100), run `fvm dart run custom_lint` and
read the violations. For each metric, decide: lower the threshold to just above the
healthy bulk and refactor the genuine outliers above it, OR `// ignore: <rule>` +
reason a justified one-off. Record the final chosen numbers in the config block.
Re-run until `No issues found!`. (Hard-gate: the pass MUST end green.)

- [ ] **Step 5: Run the full done-bar**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart format --output=none --set-exit-if-changed lib test tools && fvm flutter test`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml lib
git commit -m "feat(analysis): add solid_lints complexity metrics (3 cherry-picked rules)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 8: Supply chain (F) — OSV-Scanner CI job + Dependabot

Independent of the lint work; no app-code changes.

**Files:**
- Create: `.github/dependabot.yml`
- Modify: `.github/workflows/ci.yml` (add an OSV-Scanner job)

**Interfaces:**
- Consumes: `pubspec.lock`, the workflow action versions. Produces: a new CI job + weekly Dependabot PRs.

- [ ] **Step 1: Add Dependabot config**

`.github/dependabot.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      pub-dependencies:
        patterns: ["*"]
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      actions:
        patterns: ["*"]
```

- [ ] **Step 2: Add the OSV-Scanner job to ci.yml**

In `.github/workflows/ci.yml`, add a second job under `jobs:` (sibling of `checks:`):
```yaml
  osv-scan:
    name: OSV-Scanner (dependency vulnerabilities)
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - name: Run OSV-Scanner on pubspec.lock
        uses: google/osv-scanner-action@v1
        with:
          scan-args: |-
            --lockfile=./pubspec.lock
```
Verify the action ref (`google/osv-scanner-action@v1`) and `scan-args` shape against
the current README at https://github.com/google/osv-scanner-action at implementation
time; pin to the latest tagged major. If the repo's first-party reusable workflow is
preferred, use that form instead.

- [ ] **Step 3: Validate the workflow YAML locally**

Run: `fvm dart run custom_lint >/dev/null 2>&1; python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); yaml.safe_load(open('.github/dependabot.yml')); print('yaml ok')"`
Expected: `yaml ok` (syntactic validation; full run happens on push).

- [ ] **Step 4: Commit**

```bash
git add .github/dependabot.yml .github/workflows/ci.yml
git commit -m "ci: add OSV-Scanner job + Dependabot (pub + github-actions)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 9: Unused code/files (E) — DCM in CI

DCM runs as an external CLI (bundles its own analyzer → no interaction with the pub
analyzer pin). Free tier covers both commands; CI needs a free license key secret.

**Files:**
- Modify: `.github/workflows/ci.yml` (add a DCM job)
- Modify: `.githooks/pre-commit` (add a guarded local DCM step)

**Interfaces:**
- Consumes: the `DCM_CI_KEY` repo secret (user-provided). Produces: two gating checks `dcm check-unused-code lib` + `dcm check-unused-files lib`.

- [ ] **Step 1: Confirm DCM CI mechanics against current docs**

Read https://dcm.dev/docs/teams/ci-integrations/github-actions/ to confirm: the
setup action name + inputs, the activation command, and the secret variable name.
The canonical pattern (verify, then use) is `CQLabs/setup-dcm@v…` to install +
activate, then `dcm` commands. Record the exact action ref + inputs used.

- [ ] **Step 2: Add the DCM job to ci.yml**

In `.github/workflows/ci.yml`, add under `jobs:`:
```yaml
  dcm:
    name: DCM (unused code & files)
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get
      - name: Setup DCM
        uses: CQLabs/setup-dcm@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
      - name: Activate DCM (free tier)
        run: dcm activate --license-key="${{ secrets.DCM_CI_KEY }}"
      - name: Check unused code
        run: dcm check-unused-code lib --fatal-found
      - name: Check unused files
        run: dcm check-unused-files lib --fatal-found
```
Adjust action ref/inputs/flags to match Step 1's findings (e.g. activation may be
folded into `setup-dcm`; flag may be `--fatal-unused` rather than `--fatal-found`).

- [ ] **Step 3: Add a guarded local hook step**

In `.githooks/pre-commit`, after the `bloc lint` step and before the success print,
add:
```bash
if command -v dcm >/dev/null 2>&1; then
  step "dcm (unused code & files)"
  dcm check-unused-code lib --fatal-found \
    && dcm check-unused-files lib --fatal-found \
    || fail "DCM found unused code/files"
else
  printf '  (dcm not installed — skipping unused-code/files locally; CI enforces it)\n'
fi
```

- [ ] **Step 4: Run DCM locally if installed, and clean up dead code**

If `dcm` is installed locally, run:
```bash
dcm check-unused-code lib && dcm check-unused-files lib
```
For each finding: delete genuinely-dead code (e.g. the unwired `AppDropdown<T>` noted
in CLAUDE.md §4.8), or suppress an intentionally-retained item per DCM's ignore
mechanism + a reason. If `dcm` is not installed locally, this cleanup happens on the
first CI run; note that in the handoff. Re-run the app done-bar after any deletion:
`fvm flutter analyze && fvm dart run custom_lint && fvm flutter test`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml .githooks/pre-commit lib
git commit -m "ci: add DCM unused-code/files gate (+ guarded local hook step)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

### Task 10: Wire the lint fixtures into the gates + update docs

Make the `getman_lints` fixtures part of CI/hook so the rules stay tested, extend the
PR summary comment, and sync CLAUDE.md.

**Files:**
- Modify: `.githooks/pre-commit` (run the fixtures custom_lint)
- Modify: `.github/workflows/ci.yml` (run the fixtures custom_lint) + the summary-comment builder
- Modify: `CLAUDE.md` (§5 verification bar + §7 mandates)

**Interfaces:**
- Consumes: everything above. Produces: the final gated, documented state.

- [ ] **Step 1: Run the lint fixtures in the pre-commit hook**

In `.githooks/pre-commit`, immediately after the existing `custom_lint` step, add:
```bash
step "custom_lint fixtures (getman_lints self-test)"
( cd tools/getman_lints/example && $DART run custom_lint ) \
  || fail "getman_lints fixtures failed — a rule regressed"
```

- [ ] **Step 2: Run the lint fixtures in CI**

In `.github/workflows/ci.yml` `checks:` job, after the `custom_lint` step add a step:
```yaml
      - name: custom_lint fixtures (getman_lints self-test)
        id: lint_fixtures
        continue-on-error: true
        run: |
          cd tools/getman_lints/example
          dart pub get
          dart run custom_lint 2>&1 | tee ../../../lint_fixtures.log
```
Then add `LINT_FIXTURES: ${{ steps.lint_fixtures.outcome }}` to the summary step's
`env:`, a `| \`lint fixtures\` | $(icon "$LINT_FIXTURES") |` table row, an
`append_log "lint fixtures" "$LINT_FIXTURES" lint_fixtures.log` call, and
`steps.lint_fixtures.outcome != 'success' ||` to the final "Fail if any check failed"
condition.

- [ ] **Step 3: Update CLAUDE.md §5 (verification bar)**

Add the new gates to the command list / done-bar in §5: the four new `getman_lints`
rules + three `solid_lints` metrics run under the existing `custom_lint` pass; the
`getman_lints` fixtures self-test (`cd tools/getman_lints/example && dart run
custom_lint`); DCM unused-code/files; OSV-Scanner. State that DCM + OSV are
CI-enforced (DCM also local-if-installed).

- [ ] **Step 4: Update CLAUDE.md §7 (mandates) and the §1/§6 lint notes**

Document: the four new architecture rules and what each forbids; the `*_io.dart`
platform-safety convention as machine-enforced; the metrics budget (final
thresholds); `close_sinks`/`discarded_futures` now on; that new custom_lint rules
ship with `// expect_lint:` fixtures in `tools/getman_lints/example/`.

- [ ] **Step 5: Final full done-bar**

Run:
```bash
fvm flutter analyze && \
fvm dart run custom_lint && \
( cd tools/getman_lints/example && fvm dart run custom_lint ) && \
fvm dart run bloc_tools:bloc lint lib </dev/null && \
fvm dart format --output=none --set-exit-if-changed lib test tools && \
fvm flutter test
```
Expected: every command green.

- [ ] **Step 6: Commit**

```bash
git add .githooks/pre-commit .github/workflows/ci.yml CLAUDE.md
git commit -m "ci+docs: gate getman_lints fixtures; document the hardened analysis stack

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VqqQry8Twe79wrh7jGQogF"
```

---

## Self-Review

**Spec coverage:**
- A1/A2/A3 → Tasks 2/3/4. ✅
- B (`equatable_props_complete`, hand-written) → Task 5. ✅
- C (feature isolation) → dropped, no task. ✅ (intentional)
- D (`solid_lints` metrics) → Task 7. ✅
- E (DCM unused) → Task 9. ✅
- F (OSV + Dependabot) → Task 8. ✅
- G (`close_sinks` + `discarded_futures`) → Task 6. ✅
- Wiring (pre-commit, CI, summary comment, CLAUDE.md) → Tasks 8/9/10. ✅
- Test harness (custom_lint had none) → Task 1 (spec §4 "ships tests" made concrete). ✅

**Placeholder scan:** Thresholds in Task 7 and external-action refs/flags in Tasks
8/9 are data-/doc-dependent and carry explicit derive-and-verify steps, not blind
TODOs. No "implement later" / "add error handling" placeholders.

**Type consistency:** Lint names are stable across tasks (`domain_no_infrastructure_imports`,
`bloc_depends_on_abstractions`, `platform_io_outside_io_files`, `equatable_props_complete`).
The shared `_posix` helper and `addImportDirective`/`addClassDeclaration` registry
methods are used consistently. The fixtures test command is identical everywhere.

**Known risks carried forward (from spec §7):** analyzer-8.4 element/AST accessor
names in Task 5 (mitigated by the fixtures loop + an explicit adjust note);
`solid_lints` opt-in mechanic in Task 7 (mitigated by the Step 3 verification);
DCM/OSV action specifics in Tasks 8/9 (mitigated by doc-check steps).

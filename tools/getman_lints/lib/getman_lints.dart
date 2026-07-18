import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Entry point discovered by custom_lint. Registers Getman's project-local
/// architecture rules (see CLAUDE.md "Mandatory rules").
PluginBase createPlugin() => _GetmanLints();

class _GetmanLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
    AvoidGetItInWidgets(),
    AvoidHardcodedBrandColors(),
    DomainNoInfrastructureImports(),
    BlocDependsOnAbstractions(),
    PlatformIoOutsideIoFiles(),
    EquatablePropsComplete(),
    FileHeaderRequired(),
  ];
}

/// `path` with backslashes normalized to `/`, so the file checks below behave
/// identically on Windows and POSIX.
String _posix(String path) => path.replaceAll(r'\', '/');

/// Enforces "GetIt stays in DI" (CLAUDE.md "Mandatory rules"): the `sl`
/// service locator and the `GetIt` type may only be referenced from DI setup
/// (`lib/core/di/`) and the app entry point (`lib/main.dart`). Everywhere
/// else, services must be injected via BlocProvider / RepositoryProvider /
/// constructor injection.
class AvoidGetItInWidgets extends DartLintRule {
  const AvoidGetItInWidgets() : super(code: _code);

  static const _code = LintCode(
    name: 'avoid_get_it_in_widgets',
    problemMessage:
        'Do not reference the GetIt service locator (`sl`) or `GetIt` outside '
        'DI setup. Inject services via BlocProvider, RepositoryProvider, or '
        'the constructor instead (CLAUDE.md "Mandatory rules").',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final path = _posix(resolver.path);
    // Only guard production code; the DI container and the entry point are the
    // sanctioned locator sites. Tests may wire the locator freely.
    if (!path.contains('/lib/') ||
        path.contains('/lib/core/di/') ||
        path.endsWith('/lib/main.dart')) {
      return;
    }

    context.registry.addSimpleIdentifier((node) {
      final element = node.element;
      if (element == null) return;

      final library = element.library?.uri.toString() ?? '';

      final isLocator =
          element.name == 'sl' &&
          library.endsWith('/core/di/injection_container.dart');
      final isGetItType =
          element.name == 'GetIt' && library.startsWith('package:get_it/');

      if (isLocator || isGetItType) {
        reporter.atNode(node, _code);
      }
    });
  }
}

/// Enforces "never hardcode themeable colors" (docs/architecture/theming.md):
/// bans `Colors.black* / Colors.white* / Colors.red*` outside the theme layer
/// (`lib/core/theme/`, where raw palette colors legitimately live). Pull colors
/// from theme extensions (`context.appPalette`) or `colorScheme` instead.
///
/// The documented exception — `Colors.white`/`black` as deliberate contrast on
/// a variable-colored badge — is silenced per line with
/// `// ignore: avoid_hardcoded_brand_colors` and a justifying comment.
class AvoidHardcodedBrandColors extends DartLintRule {
  const AvoidHardcodedBrandColors() : super(code: _code);

  static const _code = LintCode(
    name: 'avoid_hardcoded_brand_colors',
    problemMessage:
        'Do not hardcode Colors.black/white/red on themeable surfaces. Read '
        'colors from theme extensions (context.appPalette) or colorScheme '
        '(docs/architecture/theming.md).',
    errorSeverity: ErrorSeverity.WARNING,
  );

  static const _bannedFamilies = ['black', 'white', 'red'];

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final path = _posix(resolver.path);
    // The theme layer is where raw colors are defined on purpose.
    if (!path.contains('/lib/') || path.contains('/lib/core/theme/')) return;

    context.registry.addPrefixedIdentifier((node) {
      if (node.prefix.name != 'Colors') return;

      // If `Colors` resolves, require it to be Material's (skip a user-defined
      // class that happens to be named `Colors`); if it doesn't resolve, the
      // name match alone is enough to flag.
      final prefixElement = node.prefix.element;
      final library = prefixElement?.library?.uri.toString() ?? '';
      if (prefixElement != null && !library.contains('material')) return;

      final name = node.identifier.name;
      final isBanned = _bannedFamilies.any(name.startsWith);
      if (isBanned) {
        reporter.atNode(node, _code);
      }
    });
  }
}

/// Enforces "BLoCs depend on abstract Repository types, never ...Impl/Hive/Dio
/// directly" (CLAUDE.md "Mandatory rules"): a `*_bloc.dart` / `*_cubit.dart`
/// file may not import a data/ layer, dio, or hive. Detection is by import
/// directory/package, not an `Impl` name heuristic.
class BlocDependsOnAbstractions extends DartLintRule {
  const BlocDependsOnAbstractions() : super(code: _code);

  static const _code = LintCode(
    name: 'bloc_depends_on_abstractions',
    problemMessage:
        'BLoCs/Cubits must depend on abstract Repository types. Do not import a '
        'data/ layer, dio, or hive directly from a bloc/cubit '
        '(CLAUDE.md "Mandatory rules").',
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

/// Enforces web-safety (docs/architecture/settings-history-updates.md):
/// dart:io / updat / path_provider / package_info_plus may only be imported
/// from `*_io.dart` files (the conditional-import native-side convention).
/// Keeps web builds clean.
class PlatformIoOutsideIoFiles extends DartLintRule {
  const PlatformIoOutsideIoFiles() : super(code: _code);

  static const _code = LintCode(
    name: 'platform_io_outside_io_files',
    problemMessage:
        'dart:io / updat / path_provider / package_info_plus may only be '
        'imported from a *_io.dart file (conditional-import native side). Move '
        'native code behind an *_io.dart + stub split to keep web builds clean '
        '(docs/architecture/settings-history-updates.md).',
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
///
/// Placement matters: the diagnostic is anchored to the class name token, so
/// the `// ignore: equatable_props_complete` must sit directly above the
/// class declaration — not above a field — or the ignore won't suppress it.
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

      // Collect declared instance field names (static fields are excluded).
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

/// Enforces "domain layer has zero imports from data/ or Flutter UI"
/// (CLAUDE.md "Mandatory rules"): a file under any `domain/` directory may
/// import only pure Dart + equatable — never Flutter, dart:io/dart:ui, dio,
/// hive, or a feature's data/.
class DomainNoInfrastructureImports extends DartLintRule {
  const DomainNoInfrastructureImports() : super(code: _code);

  static const _code = LintCode(
    name: 'domain_no_infrastructure_imports',
    problemMessage:
        'The domain layer must be pure Dart + equatable. Do not import Flutter, '
        'dart:io/dart:ui, dio, hive, or a feature data/ layer from domain/ '
        '(CLAUDE.md "Mandatory rules").',
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

/// Enforces the file-header mandate (CLAUDE.md "Design for Claude"): every
/// hand-written file under lib/ opens with a `//` prose comment describing
/// what lives in it. Lint-plumbing comments (`// ignore...`,
/// `// expect_lint...`) don't count as headers. Reported at the first token
/// (not offset 0) so `// expect_lint:` fixtures can precede it.
class FileHeaderRequired extends DartLintRule {
  const FileHeaderRequired() : super(code: _code);

  static const _code = LintCode(
    name: 'file_header_required',
    problemMessage:
        'File must open with a `//` header comment describing its purpose '
        '(what lives here; for services also collaborators + wiring). See '
        'CLAUDE.md "Design for Claude".',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final path = _posix(resolver.path);
    if (!path.contains('/lib/') || path.endsWith('.g.dart')) return;

    context.registry.addCompilationUnit((unit) {
      Token? comment = unit.beginToken.precedingComments;
      while (comment != null) {
        final text = comment.lexeme;
        final isPlumbing =
            text.startsWith('// ignore') || text.startsWith('// expect_lint');
        if (!isPlumbing) return; // a real header exists
        comment = comment.next;
      }
      reporter.atOffset(
        offset: unit.beginToken.offset,
        length: unit.beginToken.length,
        diagnosticCode: _code,
      );
    });
  }
}

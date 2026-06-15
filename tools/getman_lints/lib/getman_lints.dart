import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Entry point discovered by custom_lint. Registers Getman's project-local
/// architecture rules (see CLAUDE.md §7 Development Mandates).
PluginBase createPlugin() => _GetmanLints();

class _GetmanLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
    AvoidGetItInWidgets(),
    AvoidHardcodedBrandColors(),
  ];
}

/// `path` with backslashes normalized to `/`, so the file checks below behave
/// identically on Windows and POSIX.
String _posix(String path) => path.replaceAll(r'\', '/');

/// Enforces "GetIt stays in DI" (CLAUDE.md §7): the `sl` service locator and
/// the `GetIt` type may only be referenced from DI setup (`lib/core/di/`) and
/// the app entry point (`lib/main.dart`). Everywhere else, services must be
/// injected via BlocProvider / RepositoryProvider / constructor injection.
class AvoidGetItInWidgets extends DartLintRule {
  const AvoidGetItInWidgets() : super(code: _code);

  static const _code = LintCode(
    name: 'avoid_get_it_in_widgets',
    problemMessage:
        'Do not reference the GetIt service locator (`sl`) or `GetIt` outside '
        'DI setup. Inject services via BlocProvider, RepositoryProvider, or '
        'the constructor instead (CLAUDE.md §7).',
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

/// Enforces "never hardcode themeable colors" (CLAUDE.md §4.8): bans
/// `Colors.black* / Colors.white* / Colors.red*` outside the theme layer
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
        '(CLAUDE.md §4.8).',
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

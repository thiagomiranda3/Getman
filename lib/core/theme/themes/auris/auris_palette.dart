import 'package:auris/auris.dart';
import 'package:getman/core/theme/extensions/app_palette.dart';

/// Maps [AurisScheme] tokens onto [AppPalette] fields.
///
/// All colors come from the scheme (resolved at call-site for the brightness),
/// so light and dark themes automatically produce the right semantic colors
/// without any hardcoded Color literals.
AppPalette aurisPalette(AurisScheme scheme) {
  return AppPalette(
    methodColors: {
      'GET': scheme.success,
      'POST': scheme.primaryActive, // gold
      'PUT': scheme.secondary, // slate
      'PATCH': scheme.primaryHighlight,
      'DELETE': scheme.dangerBright,
      'HEAD': scheme.secondaryDim,
      'OPTIONS': scheme.secondaryDim,
    },
    methodFallback: scheme.textMid,
    statusSuccess: scheme.success,
    statusWarning: scheme.primaryActive,
    statusError: scheme.danger,
    statusAccentSuccess: scheme.successBright,
    statusAccentWarning: scheme.primaryHighlight,
    statusAccentError: scheme.dangerBright,
    codeBackground: scheme.surfaceInset,
    variableResolved: scheme.successBright,
    variableUnresolved: scheme.dangerBright,
    selectorActive: scheme.primaryActive,
    diffAddedBackground: scheme.success.withValues(alpha: 0.12),
    diffAddedForeground: scheme.successBright,
    diffRemovedBackground: scheme.danger.withValues(alpha: 0.12),
    diffRemovedForeground: scheme.dangerBright,
  );
}

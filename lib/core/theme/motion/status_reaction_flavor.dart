import 'package:getman/core/theme/motion/theme_reaction.dart';

/// Presentation-layer refinement of a [ThemeReaction] into a fine-grained
/// "flavor". The coarse [ThemeReactionKind] stays the bloc currency; this adds
/// the HTTP-status semantics once, in the theme layer, where the visual idiom
/// lives. Pure Dart (no Flutter import).
enum StatusReactionFlavor {
  ok,
  created,
  noContent,
  notModified,
  unauthorized,
  forbidden,
  notFound,
  timeout,
  rateLimited,
  clientError,
  serverCrash,
  serviceUnavailable,
  serverError,
  networkError,
  badCertificate,
  cancelled,
}

/// Classifies a terminal reaction. `sendStarted` is not a resolution; it maps
/// to [StatusReactionFlavor.ok] defensively (overlays never call this on it).
StatusReactionFlavor flavorFor(ThemeReaction r) {
  switch (r.kind) {
    case ThemeReactionKind.cancelled:
      return StatusReactionFlavor.cancelled;
    case ThemeReactionKind.networkError:
      return switch (r.transportFailure) {
        TransportFailureKind.timeout => StatusReactionFlavor.timeout,
        TransportFailureKind.badCertificate =>
          StatusReactionFlavor.badCertificate,
        null => StatusReactionFlavor.networkError,
      };
    case ThemeReactionKind.sendStarted:
      return StatusReactionFlavor.ok;
    case ThemeReactionKind.success:
    case ThemeReactionKind.clientError:
    case ThemeReactionKind.serverError:
      final code = r.statusCode;
      return code == null ? _fallbackForKind(r.kind) : _flavorForCode(code);
  }
}

StatusReactionFlavor _flavorForCode(int code) {
  switch (code) {
    case 201:
      return StatusReactionFlavor.created;
    case 204:
      return StatusReactionFlavor.noContent;
    case 304:
      return StatusReactionFlavor.notModified;
    case 401:
      return StatusReactionFlavor.unauthorized;
    case 403:
      return StatusReactionFlavor.forbidden;
    case 404:
      return StatusReactionFlavor.notFound;
    case 408:
      return StatusReactionFlavor.timeout;
    case 429:
      return StatusReactionFlavor.rateLimited;
    case 500:
      return StatusReactionFlavor.serverCrash;
    case 503:
      return StatusReactionFlavor.serviceUnavailable;
  }
  if (code >= 200 && code < 400) return StatusReactionFlavor.ok;
  if (code >= 400 && code < 500) return StatusReactionFlavor.clientError;
  if (code >= 500 && code < 600) return StatusReactionFlavor.serverError;
  return StatusReactionFlavor.networkError;
}

StatusReactionFlavor _fallbackForKind(ThemeReactionKind kind) => switch (kind) {
  ThemeReactionKind.clientError => StatusReactionFlavor.clientError,
  ThemeReactionKind.serverError => StatusReactionFlavor.serverError,
  ThemeReactionKind.success => StatusReactionFlavor.ok,
  ThemeReactionKind.sendStarted => StatusReactionFlavor.ok,
  ThemeReactionKind.networkError => StatusReactionFlavor.networkError,
  ThemeReactionKind.cancelled => StatusReactionFlavor.cancelled,
};

import 'package:equatable/equatable.dart';
import 'package:getman/core/utils/cookie_parser.dart';

/// A stored cookie with just enough attributes to decide when to send it back.
///
/// Expiry: only `Max-Age` is honored precisely (it's a simple seconds offset).
/// A cookie with only an `Expires` HTTP-date is treated as a session cookie —
/// parsing RFC HTTP dates without dart:io is out of scope for v1 (documented).
class NetworkCookie extends Equatable {
  const NetworkCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
    this.expiresEpochMs,
    this.hostOnly = false,
  });
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;

  /// Absolute expiry in epoch ms, or null for a session cookie.
  final int? expiresEpochMs;

  /// RFC 6265 §5.1.3: when the `Set-Cookie` carried no `Domain` attribute the
  /// cookie is host-only and must match the request host **exactly** (never a
  /// subdomain). Defaults to false so legacy persisted cookies (missing the
  /// field) keep the pre-fix suffix-matching behavior.
  final bool hostOnly;

  /// Identity for upsert: a server overwriting (domain, path, name) replaces.
  String get key => '$domain|$path|$name';

  bool isExpired(int nowEpochMs) =>
      expiresEpochMs != null && expiresEpochMs! <= nowEpochMs;

  /// Whether this cookie should be sent on a request to [uri].
  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final d = _stripLeadingDot(domain.toLowerCase());
    final domainOk = hostOnly ? host == d : (host == d || host.endsWith('.$d'));
    if (!domainOk) return false;
    if (!_pathMatches(uri.path.isEmpty ? '/' : uri.path)) return false;
    if (secure && uri.scheme != 'https') return false;
    return true;
  }

  /// RFC 6265 §5.1.4 path-match: equal, or a prefix ending on a `/` boundary,
  /// so `Path=/api` matches `/api` and `/api/x` but not the sibling `/apixyz`.
  bool _pathMatches(String requestPath) {
    if (path == '/' || requestPath == path) return true;
    if (!requestPath.startsWith(path)) return false;
    return path.endsWith('/') || requestPath[path.length] == '/';
  }

  /// Parses a `Set-Cookie` header (possibly carrying several cookies) into
  /// [NetworkCookie]s, defaulting domain/path from [requestUri].
  static List<NetworkCookie> parseSetCookie(
    String? header, {
    required Uri requestUri,
    required int nowEpochMs,
  }) {
    final result = <NetworkCookie>[];
    for (final c in CookieParser.parse(header)) {
      var domain = requestUri.host;
      var hostOnly = true; // no Domain attribute → host-only (RFC 6265 §5.1.3)
      String? explicitPath;
      var secure = false;
      var httpOnly = false;
      int? expires;
      for (final attr in c.attributes.split(';')) {
        final a = attr.trim();
        final lower = a.toLowerCase();
        if (lower.startsWith('domain=')) {
          final dv = _stripLeadingDot(a.substring(7).trim());
          // An empty Domain attribute is ignored → the cookie stays host-only.
          if (dv.isNotEmpty) {
            domain = dv;
            hostOnly = false;
          }
        } else if (lower.startsWith('path=')) {
          final p = a.substring(5).trim();
          // RFC 6265 §5.2.4: a Path value not starting with '/' is discarded,
          // so the default-path (request-URI directory) applies instead.
          if (p.startsWith('/')) explicitPath = p;
        } else if (lower == 'secure') {
          secure = true;
        } else if (lower == 'httponly') {
          httpOnly = true;
        } else if (lower.startsWith('max-age=')) {
          final secs = int.tryParse(a.substring(8).trim());
          if (secs != null) expires = nowEpochMs + secs * 1000;
        }
      }
      final path = explicitPath ?? _defaultPath(requestUri);
      if (domain.isEmpty) domain = requestUri.host;
      // RFC 6265 §5.3.6: a Domain attribute must cover the request host —
      // otherwise any server could plant cookies for arbitrary sites
      // (Domain=bank.com from evil.com). The single-label check on the
      // suffix arm is a pragmatic public-suffix guard (rejects Domain=com)
      // without shipping the full PSL; multi-label suffixes like co.uk are
      // not caught.
      final host = requestUri.host.toLowerCase();
      final d = domain.toLowerCase();
      final domainCoversHost =
          host == d || (host.endsWith('.$d') && d.contains('.'));
      if (!domainCoversHost) continue;
      result.add(
        NetworkCookie(
          name: c.name,
          value: c.value,
          domain: domain,
          path: path,
          secure: secure,
          httpOnly: httpOnly,
          expiresEpochMs: expires,
          hostOnly: hostOnly,
        ),
      );
    }
    return result;
  }

  static String _stripLeadingDot(String d) =>
      d.startsWith('.') ? d.substring(1) : d;

  /// RFC 6265 §5.1.4 default-path: the request URI's directory — everything up
  /// to (but excluding) the rightmost `/`. A rootless or single-segment path
  /// yields `/`.
  static String _defaultPath(Uri uri) {
    final p = uri.path;
    if (p.isEmpty || !p.startsWith('/')) return '/';
    final lastSlash = p.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : p.substring(0, lastSlash);
  }

  NetworkCookie copyWith({String? value, int? expiresEpochMs}) => NetworkCookie(
    name: name,
    value: value ?? this.value,
    domain: domain,
    path: path,
    secure: secure,
    httpOnly: httpOnly,
    expiresEpochMs: expiresEpochMs ?? this.expiresEpochMs,
    hostOnly: hostOnly,
  );

  @override
  List<Object?> get props => [
    name,
    value,
    domain,
    path,
    secure,
    httpOnly,
    expiresEpochMs,
    hostOnly,
  ];
}

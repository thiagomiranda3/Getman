import 'package:equatable/equatable.dart';
import 'package:getman/core/utils/cookie_parser.dart';

/// A stored cookie with just enough attributes to decide when to send it back.
///
/// Expiry: only `Max-Age` is honored precisely (it's a simple seconds offset).
/// A cookie with only an `Expires` HTTP-date is treated as a session cookie —
/// parsing RFC HTTP dates without dart:io is out of scope for v1 (documented).
class NetworkCookie extends Equatable {
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;

  /// Absolute expiry in epoch ms, or null for a session cookie.
  final int? expiresEpochMs;

  const NetworkCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
    this.expiresEpochMs,
  });

  /// Identity for upsert: a server overwriting (domain, path, name) replaces.
  String get key => '$domain|$path|$name';

  bool isExpired(int nowEpochMs) =>
      expiresEpochMs != null && expiresEpochMs! <= nowEpochMs;

  /// Whether this cookie should be sent on a request to [uri].
  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final d = _stripLeadingDot(domain.toLowerCase());
    final domainOk = host == d || host.endsWith('.$d');
    if (!domainOk) return false;
    if (!(path == '/' || uri.path.startsWith(path))) return false;
    if (secure && uri.scheme != 'https') return false;
    return true;
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
      var path = '/';
      var secure = false;
      var httpOnly = false;
      int? expires;
      for (final attr in c.attributes.split(';')) {
        final a = attr.trim();
        final lower = a.toLowerCase();
        if (lower.startsWith('domain=')) {
          domain = _stripLeadingDot(a.substring(7).trim());
        } else if (lower.startsWith('path=')) {
          final p = a.substring(5).trim();
          if (p.isNotEmpty) path = p;
        } else if (lower == 'secure') {
          secure = true;
        } else if (lower == 'httponly') {
          httpOnly = true;
        } else if (lower.startsWith('max-age=')) {
          final secs = int.tryParse(a.substring(8).trim());
          if (secs != null) expires = nowEpochMs + secs * 1000;
        }
      }
      if (domain.isEmpty) domain = requestUri.host;
      result.add(NetworkCookie(
        name: c.name,
        value: c.value,
        domain: domain,
        path: path,
        secure: secure,
        httpOnly: httpOnly,
        expiresEpochMs: expires,
      ));
    }
    return result;
  }

  static String _stripLeadingDot(String d) => d.startsWith('.') ? d.substring(1) : d;

  NetworkCookie copyWith({String? value, int? expiresEpochMs}) => NetworkCookie(
        name: name,
        value: value ?? this.value,
        domain: domain,
        path: path,
        secure: secure,
        httpOnly: httpOnly,
        expiresEpochMs: expiresEpochMs ?? this.expiresEpochMs,
      );

  @override
  List<Object?> get props => [name, value, domain, path, secure, httpOnly, expiresEpochMs];
}

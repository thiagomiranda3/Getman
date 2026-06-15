import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';

/// In-memory cookie jar backed by a [CookiePersistence]. The in-memory list is
/// the session source of truth; mutations flush to durable storage. Expired
/// cookies are pruned on read. [now] is injectable for deterministic tests.
class InMemoryCookieStore implements CookieStore {
  final CookiePersistence persistence;
  final int Function() now;
  final List<NetworkCookie> _cookies = [];

  InMemoryCookieStore({
    required this.persistence,
    int Function()? now,
  }) : now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Loads persisted cookies into memory (call once at boot).
  void hydrate() {
    _cookies
      ..clear()
      ..addAll(persistence.loadAll());
    _pruneExpired();
  }

  @override
  String? cookieHeaderFor(Uri uri) {
    final n = now();
    final matching = _cookies.where((c) => !c.isExpired(n) && c.matches(uri)).toList()
      // RFC 6265 §5.4: cookies with longer paths sort before shorter ones, so a
      // more-specific cookie wins for servers that read the first value of a
      // duplicated name.
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    if (matching.isEmpty) return null;
    return matching.map((c) => '${c.name}=${c.value}').join('; ');
  }

  @override
  void storeFromSetCookie(Uri requestUri, String setCookieHeader) {
    final parsed = NetworkCookie.parseSetCookie(
      setCookieHeader,
      requestUri: requestUri,
      nowEpochMs: now(),
    );
    if (parsed.isEmpty) return;
    for (final cookie in parsed) {
      _cookies.removeWhere((c) => c.key == cookie.key);
      // A server can delete a cookie by setting it already-expired; honor that
      // by simply not re-adding an expired one. Persist incrementally — one
      // put/delete per affected cookie, not a whole-jar rewrite. Best-effort:
      // never block the request path on a write.
      if (cookie.isExpired(now())) {
        persistence.remove(cookie.key);
      } else {
        _cookies.add(cookie);
        persistence.upsert(cookie);
      }
    }
  }

  @override
  List<NetworkCookie> all() => List.unmodifiable(_cookies);

  @override
  Future<void> remove(NetworkCookie cookie) async {
    _cookies.removeWhere((c) => c.key == cookie.key);
    await persistence.remove(cookie.key);
  }

  @override
  Future<void> clear() async {
    _cookies.clear();
    await persistence.clearAll();
  }

  void _pruneExpired() {
    final n = now();
    _cookies.removeWhere((c) => c.isExpired(n));
  }
}

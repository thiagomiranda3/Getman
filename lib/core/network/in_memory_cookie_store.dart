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
    final matching = _cookies.where((c) => !c.isExpired(n) && c.matches(uri));
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
      // by simply not re-adding an expired one.
      if (!cookie.isExpired(now())) _cookies.add(cookie);
    }
    _persist();
  }

  @override
  List<NetworkCookie> all() => List.unmodifiable(_cookies);

  @override
  Future<void> clear() async {
    _cookies.clear();
    await persistence.clearAll();
  }

  void _pruneExpired() {
    final n = now();
    _cookies.removeWhere((c) => c.isExpired(n));
  }

  void _persist() {
    // Best-effort durability; never block the request path on a write failure.
    persistence.saveAll(List.of(_cookies));
  }
}

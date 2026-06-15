import 'package:getman/core/network/network_cookie.dart';

/// The cookie jar as seen by the request interceptor. Implementations decide
/// matching/expiry; persistence is delegated to [CookiePersistence].
abstract class CookieStore {
  /// `name=value; name2=value2` for cookies that match [uri], or null if none.
  String? cookieHeaderFor(Uri uri);

  /// Stores cookies parsed from a response's `Set-Cookie` header.
  void storeFromSetCookie(Uri requestUri, String setCookieHeader);

  /// Snapshot of all stored cookies (for a manager UI).
  List<NetworkCookie> all();

  /// Removes a single [cookie] (matched by its `domain|path|name` key) from
  /// memory and durable storage. No-op when it is not present.
  Future<void> remove(NetworkCookie cookie);

  /// Removes every cookie from memory and durable storage.
  Future<void> clear();
}

/// Durable backing for the cookie jar. Implemented over Hive in the data layer;
/// kept abstract here so the store stays testable without Hive.
abstract class CookiePersistence {
  List<NetworkCookie> loadAll();

  /// Inserts or overwrites a single cookie (keyed by [NetworkCookie.key]).
  Future<void> upsert(NetworkCookie cookie);

  /// Removes a single cookie by its [NetworkCookie.key].
  Future<void> remove(String key);

  Future<void> clearAll();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/in_memory_cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';

class _FakePersistence implements CookiePersistence {
  List<NetworkCookie> stored;
  final List<NetworkCookie> upserted = [];
  final List<String> removed = [];
  bool cleared = false;
  _FakePersistence([this.stored = const []]);

  @override
  List<NetworkCookie> loadAll() => stored;
  @override
  Future<void> upsert(NetworkCookie cookie) async => upserted.add(cookie);
  @override
  Future<void> remove(String key) async => removed.add(key);
  @override
  Future<void> clearAll() async => cleared = true;
}

void main() {
  late _FakePersistence persistence;
  int clock = 1000;
  late InMemoryCookieStore store;

  setUp(() {
    persistence = _FakePersistence();
    clock = 1000;
    store = InMemoryCookieStore(persistence: persistence, now: () => clock);
  });

  test('hydrate loads persisted cookies', () {
    persistence = _FakePersistence([
      const NetworkCookie(name: 'a', value: '1', domain: 'api.dev'),
    ]);
    store = InMemoryCookieStore(persistence: persistence, now: () => clock);
    store.hydrate();
    expect(store.all(), hasLength(1));
  });

  test('storeFromSetCookie upserts incrementally, then cookieHeaderFor matches', () {
    store.storeFromSetCookie(Uri.parse('https://api.dev/x'), 'sid=abc; Path=/');
    // One incremental upsert — not a whole-jar rewrite.
    expect(persistence.upserted, hasLength(1));
    expect(persistence.upserted.single.name, 'sid');
    expect(store.cookieHeaderFor(Uri.parse('https://api.dev/x')), 'sid=abc');
    // Different host → no cookies.
    expect(store.cookieHeaderFor(Uri.parse('https://other.dev/x')), isNull);
  });

  test('upsert replaces a cookie with the same domain/path/name', () {
    final uri = Uri.parse('https://api.dev/');
    store.storeFromSetCookie(uri, 'sid=one');
    store.storeFromSetCookie(uri, 'sid=two');
    expect(store.all(), hasLength(1));
    expect(store.cookieHeaderFor(uri), 'sid=two');
    // Same key upserted twice (latest wins).
    expect(persistence.upserted.map((c) => c.value), ['one', 'two']);
  });

  test('an already-expired Set-Cookie removes the cookie from durable storage', () {
    final uri = Uri.parse('https://api.dev/');
    store.storeFromSetCookie(uri, 'sid=gone; Max-Age=0');
    expect(store.all(), isEmpty);
    expect(persistence.removed, isNotEmpty);
  });

  test('expired cookies are filtered out of the request header', () {
    final uri = Uri.parse('https://api.dev/');
    store.storeFromSetCookie(uri, 'sid=abc; Max-Age=10'); // expires at 1000 + 10000
    expect(store.cookieHeaderFor(uri), 'sid=abc');
    clock = 20000;
    expect(store.cookieHeaderFor(uri), isNull);
  });

  test('clear empties memory and durable storage', () async {
    store.storeFromSetCookie(Uri.parse('https://api.dev/'), 'sid=abc');
    await store.clear();
    expect(store.all(), isEmpty);
    expect(persistence.cleared, isTrue);
  });
}

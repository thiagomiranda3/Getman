import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/in_memory_cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';

class _FakePersistence implements CookiePersistence {
  List<NetworkCookie> stored;
  List<NetworkCookie>? lastSaved;
  bool cleared = false;
  _FakePersistence([this.stored = const []]);

  @override
  List<NetworkCookie> loadAll() => stored;
  @override
  Future<void> saveAll(List<NetworkCookie> cookies) async => lastSaved = cookies;
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

  test('storeFromSetCookie adds, then cookieHeaderFor returns matching cookies', () {
    store.storeFromSetCookie(Uri.parse('https://api.dev/x'), 'sid=abc; Path=/');
    expect(persistence.lastSaved, hasLength(1));
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

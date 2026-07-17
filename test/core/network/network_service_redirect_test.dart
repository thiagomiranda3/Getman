import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/cookie_interceptor.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/in_memory_cookie_store.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/network/network_service.dart';

/// One scripted response hop.
class _Hop {
  _Hop(this.status, {this.location, this.setCookie, this.body = ''});
  final int status;
  final String? location;
  final String? setCookie;
  final String body;
}

/// Returns [hops] in order (clamping to the last for any extra request) and
/// records the [RequestOptions] each hop received so redirect behavior can be
/// asserted per hop.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.hops);
  final List<_Hop> hops;
  final List<RequestOptions> requests = [];
  int _i = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final hop = hops[_i < hops.length ? _i : hops.length - 1];
    _i++;
    final headers = <String, List<String>>{
      'content-type': ['text/plain'],
      if (hop.location != null) 'location': [hop.location!],
      if (hop.setCookie != null) 'set-cookie': [hop.setCookie!],
    };
    return ResponseBody.fromString(hop.body, hop.status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

class _NoopPersistence implements CookiePersistence {
  @override
  List<NetworkCookie> loadAll() => const [];
  @override
  Future<void> upsert(NetworkCookie cookie) async {}
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> clearAll() async {}
}

typedef _Harness = ({
  NetworkService svc,
  _ScriptedAdapter adapter,
  InMemoryCookieStore store,
});

_Harness _harness(
  List<_Hop> hops, {
  NetworkConfig config = NetworkConfig.defaults,
}) {
  final store = InMemoryCookieStore(persistence: _NoopPersistence());
  final dio = NetworkService.buildDio(config, CookieInterceptor(store));
  final adapter = _ScriptedAdapter(hops);
  dio.httpClientAdapter = adapter;
  return (svc: NetworkService(dio: dio), adapter: adapter, store: store);
}

String? _headerValue(RequestOptions options, String name) {
  for (final e in options.headers.entries) {
    if (e.key.toLowerCase() == name) return e.value?.toString();
  }
  return null;
}

void main() {
  test(
    '302 captures Set-Cookie and sends it on the redirected hop (same host)',
    () async {
      final h = _harness([
        _Hop(
          302,
          location: 'https://api.dev/home',
          setCookie: 'session=xyz; Path=/',
        ),
        _Hop(200, body: 'ok'),
      ]);

      final r = await h.svc.request(
        url: 'https://api.dev/login',
        method: 'GET',
      );

      expect(r.statusCode, 200);
      expect(r.body, 'ok');
      expect(h.adapter.requests, hasLength(2));
      expect(h.adapter.requests[1].uri.toString(), 'https://api.dev/home');
      expect(
        _headerValue(h.adapter.requests[1], 'cookie'),
        contains('session=xyz'),
      );
      expect(
        h.store.cookieHeaderFor(Uri.parse('https://api.dev/home')),
        contains('session=xyz'),
      );
    },
  );

  test('303 turns the redirected request into a bodyless GET', () async {
    final h = _harness([
      _Hop(303, location: 'https://api.dev/result'),
      _Hop(200, body: 'done'),
    ]);

    final r = await h.svc.request(
      url: 'https://api.dev/submit',
      method: 'POST',
      data: 'a=1',
      headers: {'Content-Type': 'text/plain'},
    );

    expect(r.statusCode, 200);
    expect(h.adapter.requests[1].method, 'GET');
    expect(h.adapter.requests[1].data, isNull);
    expect(_headerValue(h.adapter.requests[1], 'content-type'), isNull);
  });

  test('307 preserves the method and body', () async {
    final h = _harness([
      _Hop(307, location: 'https://api.dev/retry'),
      _Hop(200, body: 'ok'),
    ]);

    await h.svc.request(
      url: 'https://api.dev/submit',
      method: 'POST',
      data: 'payload',
    );

    expect(h.adapter.requests[1].method, 'POST');
    expect(h.adapter.requests[1].data, 'payload');
  });

  test('308 preserves the method and body', () async {
    final h = _harness([
      _Hop(308, location: 'https://api.dev/retry'),
      _Hop(200, body: 'ok'),
    ]);

    await h.svc.request(
      url: 'https://api.dev/submit',
      method: 'PUT',
      data: 'payload',
    );

    expect(h.adapter.requests[1].method, 'PUT');
    expect(h.adapter.requests[1].data, 'payload');
  });

  test(
    '301 on a POST becomes a bodyless GET (browser/curl convention)',
    () async {
      final h = _harness([
        _Hop(301, location: 'https://api.dev/new'),
        _Hop(200, body: 'ok'),
      ]);

      await h.svc.request(
        url: 'https://api.dev/old',
        method: 'POST',
        data: 'x',
      );

      expect(h.adapter.requests[1].method, 'GET');
      expect(h.adapter.requests[1].data, isNull);
    },
  );

  test('302 on a non-POST keeps the method and body', () async {
    final h = _harness([
      _Hop(302, location: 'https://api.dev/new'),
      _Hop(200, body: 'ok'),
    ]);

    await h.svc.request(url: 'https://api.dev/old', method: 'PUT', data: 'x');

    expect(h.adapter.requests[1].method, 'PUT');
    expect(h.adapter.requests[1].data, 'x');
  });

  test('exceeding maxRedirects surfaces a NetworkFailure', () async {
    final h = _harness(
      [
        _Hop(302, location: 'https://api.dev/1'),
        _Hop(302, location: 'https://api.dev/2'),
        _Hop(302, location: 'https://api.dev/3'),
      ],
      config: const NetworkConfig(maxRedirects: 1),
    );

    await expectLater(
      () => h.svc.request(url: 'https://api.dev/start', method: 'GET'),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('a cross-host redirect strips the Authorization header', () async {
    final h = _harness([
      _Hop(302, location: 'https://other.dev/x'),
      _Hop(200, body: 'ok'),
    ]);

    await h.svc.request(
      url: 'https://api.dev/login',
      method: 'GET',
      headers: {'Authorization': 'Bearer secret'},
    );

    expect(h.adapter.requests[1].uri.host, 'other.dev');
    expect(_headerValue(h.adapter.requests[1], 'authorization'), isNull);
  });

  test('a same-host redirect keeps the Authorization header', () async {
    final h = _harness([
      _Hop(302, location: 'https://api.dev/x'),
      _Hop(200, body: 'ok'),
    ]);

    await h.svc.request(
      url: 'https://api.dev/login',
      method: 'GET',
      headers: {'Authorization': 'Bearer secret'},
    );

    expect(
      _headerValue(h.adapter.requests[1], 'authorization'),
      'Bearer secret',
    );
  });

  test('a relative Location is resolved against the current URI', () async {
    final h = _harness([
      _Hop(302, location: '/home'),
      _Hop(200, body: 'ok'),
    ]);

    await h.svc.request(url: 'https://api.dev/deep/login', method: 'GET');

    expect(h.adapter.requests[1].uri.toString(), 'https://api.dev/home');
  });

  test('followRedirects=false returns the 3xx response unfollowed', () async {
    final h = _harness(
      [
        _Hop(302, location: 'https://api.dev/home', body: 'redirecting'),
      ],
      config: const NetworkConfig(followRedirects: false),
    );

    final r = await h.svc.request(url: 'https://api.dev/login', method: 'GET');

    expect(r.statusCode, 302);
    expect(h.adapter.requests, hasLength(1));
  });

  test('307 re-sends a multipart FormData body on the next hop', () async {
    // Dio finalizes a FormData on send and a finalized instance cannot be
    // reused — the redirect loop must clone it per hop or the second hop
    // throws an opaque StateError (surfacing as NetworkFailure.unknown).
    final h = _harness([
      _Hop(307, location: 'https://api.dev/retry'),
      _Hop(200, body: 'ok'),
    ]);

    final r = await h.svc.request(
      url: 'https://api.dev/upload',
      method: 'POST',
      data: FormData.fromMap({'field': 'value'}),
    );

    expect(r.statusCode, 200);
    expect(h.adapter.requests, hasLength(2));
    expect(h.adapter.requests[1].method, 'POST');
    expect(h.adapter.requests[1].data, isA<FormData>());
  });

  test('a 3xx without a Location header is the final response', () async {
    final h = _harness([_Hop(304)]);

    final r = await h.svc.request(url: 'https://api.dev/x', method: 'GET');

    expect(r.statusCode, 304);
    expect(h.adapter.requests, hasLength(1));
  });
}

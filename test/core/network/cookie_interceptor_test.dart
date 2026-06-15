import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/cookie_interceptor.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';

class _FakeStore implements CookieStore {
  String? header;
  Uri? capturedUri;
  String? capturedSetCookie;

  @override
  String? cookieHeaderFor(Uri uri) => header;
  @override
  void storeFromSetCookie(Uri requestUri, String setCookieHeader) {
    capturedUri = requestUri;
    capturedSetCookie = setCookieHeader;
  }

  @override
  List<NetworkCookie> all() => const [];
  @override
  Future<void> remove(NetworkCookie cookie) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  test('onRequest sets the Cookie header from the jar', () {
    final store = _FakeStore()..header = 'a=1';
    final options = RequestOptions(path: 'https://api.dev/x');

    CookieInterceptor(store).onRequest(options, RequestInterceptorHandler());

    expect(options.headers['Cookie'], 'a=1');
  });

  test('onRequest merges with an existing Cookie header', () {
    final store = _FakeStore()..header = 'a=1';
    final options = RequestOptions(path: 'https://api.dev/x', headers: {'Cookie': 'x=0'});

    CookieInterceptor(store).onRequest(options, RequestInterceptorHandler());

    expect(options.headers['Cookie'], 'x=0; a=1');
  });

  test('onRequest does nothing when the jar is empty', () {
    final store = _FakeStore();
    final options = RequestOptions(path: 'https://api.dev/x');

    CookieInterceptor(store).onRequest(options, RequestInterceptorHandler());

    expect(options.headers.containsKey('Cookie'), isFalse);
  });

  test('onResponse hands set-cookie to the store', () {
    final store = _FakeStore();
    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: 'https://api.dev/x'),
      headers: Headers.fromMap({
        'set-cookie': ['sid=abc; Path=/'],
      }),
    );

    CookieInterceptor(store).onResponse(response, ResponseInterceptorHandler());

    expect(store.capturedUri.toString(), 'https://api.dev/x');
    expect(store.capturedSetCookie, contains('sid=abc'));
  });
}

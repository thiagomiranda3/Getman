import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:getman/core/network/cookie_store.dart';

/// Dio interceptor that sends jar cookies on requests and captures `Set-Cookie`
/// from responses. No-op on web, where the browser owns cookies and the XHR
/// adapter forbids setting the `Cookie` header anyway.
class CookieInterceptor extends Interceptor {
  CookieInterceptor(this.store);
  final CookieStore store;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!kIsWeb) {
      final jar = store.cookieHeaderFor(options.uri);
      if (jar != null && jar.isNotEmpty) {
        final existing = options.headers.entries
            .where((e) => e.key.toLowerCase() == 'cookie')
            .map((e) => e.value?.toString())
            .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
        options.headers['Cookie'] = existing == null ? jar : '$existing; $jar';
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (!kIsWeb) {
      final setCookie = response.headers.map['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        store.storeFromSetCookie(
          response.requestOptions.uri,
          setCookie.join(', '),
        );
      }
    }
    handler.next(response);
  }
}

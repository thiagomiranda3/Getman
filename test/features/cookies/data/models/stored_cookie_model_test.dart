import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';

void main() {
  test('round-trips a cookie through fromCookie/toCookie', () {
    const cookie = NetworkCookie(
      name: 'sid',
      value: 'abc',
      domain: 'api.dev',
      path: '/v1',
      secure: true,
      httpOnly: true,
      expiresEpochMs: 123456,
    );
    expect(StoredCookieModel.fromCookie(cookie).toCookie(), cookie);
  });

  test('round-trips a session cookie (null expiry)', () {
    const cookie = NetworkCookie(name: 'a', value: '1', domain: 'x');
    final back = StoredCookieModel.fromCookie(cookie).toCookie();
    expect(back.expiresEpochMs, isNull);
    expect(back, cookie);
  });
}

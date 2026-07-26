import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_methods.dart';

void main() {
  test('HttpMethods.all is the canonical method list, in order', () {
    // The single source of the supported HTTP methods — dropdowns, code-gen
    // targets, and parsers all read this list. Order is UI order.
    expect(HttpMethods.all, ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']);
  });

  test('methods are uppercase and unique', () {
    expect(HttpMethods.all.toSet().length, HttpMethods.all.length);
    for (final method in HttpMethods.all) {
      expect(method, method.toUpperCase());
    }
  });
}

// test/core/utils/openapi/spec_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart';

void main() {
  test('routes an OpenAPI 3.x map', () {
    final api = normalizeSpec({
      'openapi': '3.0.1',
      'info': {'title': 'Three'},
      'paths': <String, dynamic>{},
    });
    expect(api.title, 'Three');
  });

  test('routes a Swagger 2.0 map', () {
    final api = normalizeSpec({
      'swagger': '2.0',
      'info': {'title': 'Two'},
      'paths': <String, dynamic>{},
    });
    expect(api.title, 'Two');
  });

  test('throws FormatException when neither key is present', () {
    expect(
      () => normalizeSpec({
        'info': {'title': 'X'},
      }),
      throwsFormatException,
    );
  });
}

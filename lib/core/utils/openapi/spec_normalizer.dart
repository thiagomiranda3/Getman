// Detects whether a decoded spec map is OpenAPI 3.x or Swagger 2.0 (by the
// `openapi`/`swagger` version key) and dispatches to the matching normalizer;
// throws FormatException for anything else.

import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/openapi_v3_normalizer.dart';
import 'package:getman/core/utils/openapi/swagger_v2_normalizer.dart';

/// Detects the spec version and dispatches to the matching normalizer.
/// Throws [FormatException] if [spec] is neither OpenAPI 3.x nor Swagger 2.0.
NormalizedApi normalizeSpec(Map<String, dynamic> spec) {
  if (spec['openapi'] is String &&
      (spec['openapi'] as String).startsWith('3')) {
    return normalizeOpenApiV3(spec);
  }
  if (spec['swagger'] is String &&
      (spec['swagger'] as String).startsWith('2')) {
    return normalizeSwaggerV2(spec);
  }
  throw const FormatException(
    'Unrecognized spec — expected an "openapi: 3.x" or "swagger: 2.0" '
    'document.',
  );
}

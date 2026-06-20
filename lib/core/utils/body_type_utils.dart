import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/header_utils.dart';

/// Shared Content-Type rules per [BodyType], used by both the send-path
/// serializer and the code generator so they can't drift.
///
/// NOTE: callers own *when* to apply the binary rule. The send-path serializer
/// only invokes this for binary after confirming a file exists, so a binary
/// request with no file stays header-free (matching prior behavior); the code
/// generator applies it unconditionally because it always shows the header.
class BodyTypeUtils {
  BodyTypeUtils._();

  static void applyContentType(Map<String, String> headers, BodyType type) {
    switch (type) {
      case BodyType.urlencoded:
        HeaderUtils.setHeader(
          headers,
          'Content-Type',
          'application/x-www-form-urlencoded',
        );
      case BodyType.multipart:
        HeaderUtils.removeHeader(headers, 'content-type');
      case BodyType.binary:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          HeaderUtils.setHeader(
            headers,
            'Content-Type',
            'application/octet-stream',
          );
        }
      case BodyType.graphql:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          HeaderUtils.setHeader(headers, 'Content-Type', 'application/json');
        }
      case BodyType.none:
      case BodyType.raw:
        break;
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/header_utils.dart';

void main() {
  group('HeaderUtils.hasHeader', () {
    test('matches case-insensitively', () {
      final headers = {'Content-Type': 'application/json'};
      expect(HeaderUtils.hasHeader(headers, 'content-type'), isTrue);
      expect(HeaderUtils.hasHeader(headers, 'CONTENT-TYPE'), isTrue);
      expect(HeaderUtils.hasHeader(headers, 'authorization'), isFalse);
    });
  });

  group('HeaderUtils.setHeader', () {
    test('replaces a case-variant key instead of duplicating it', () {
      final headers = {'content-type': 'text/plain'};
      HeaderUtils.setHeader(headers, 'Content-Type', 'application/json');
      expect(headers.length, 1);
      expect(headers['Content-Type'], 'application/json');
      expect(headers.containsKey('content-type'), isFalse);
    });

    test('adds the header when absent', () {
      final headers = <String, String>{};
      HeaderUtils.setHeader(headers, 'Authorization', 'Bearer x');
      expect(headers, {'Authorization': 'Bearer x'});
    });
  });

  group('HeaderUtils.removeHeader', () {
    test('removes every case-variant', () {
      final headers = {
        'Content-Type': 'a',
        'content-type': 'b',
        'X-Other': 'c',
      };
      HeaderUtils.removeHeader(headers, 'CONTENT-TYPE');
      expect(headers, {'X-Other': 'c'});
    });
  });

  group('HeaderUtils.hasCustomContentType', () {
    test('false when absent', () {
      expect(HeaderUtils.hasCustomContentType(<String, String>{}), isFalse);
    });

    test('false when it is the JSON default (any casing/whitespace)', () {
      expect(
        HeaderUtils.hasCustomContentType({
          'content-type': ' Application/JSON ',
        }),
        isFalse,
      );
    });

    test('true when a non-default content-type is set', () {
      expect(
        HeaderUtils.hasCustomContentType({'Content-Type': 'image/png'}),
        isTrue,
      );
    });
  });
}

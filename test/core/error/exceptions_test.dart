import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';

void main() {
  group('PersistenceException', () {
    test('toString carries the message', () {
      final e = PersistenceException('box write failed');
      expect(e.toString(), 'PersistenceException: box write failed');
    });

    test('toString appends the cause when one is given', () {
      final e = PersistenceException(
        'box write failed',
        cause: const FormatException('bad bytes'),
      );
      expect(e.toString(), contains('box write failed'));
      expect(e.toString(), contains('bad bytes'));
    });

    test('is an Exception (catchable at the repository boundary)', () {
      expect(PersistenceException('x'), isA<Exception>());
    });
  });

  group('FileBodyException', () {
    test('toString names the unreadable file path', () {
      final e = FileBodyException('/tmp/upload.bin');
      expect(e.toString(), 'Could not read file: /tmp/upload.bin');
    });

    test('toString appends the cause when one is given', () {
      final e = FileBodyException('/tmp/upload.bin', cause: 'ENOENT');
      expect(e.toString(), contains('/tmp/upload.bin'));
      expect(e.toString(), contains('ENOENT'));
    });
  });

  group('GraphqlVariablesException', () {
    test('toString explains the invalid-JSON detail', () {
      final e = GraphqlVariablesException('Unexpected character at 1:3');
      expect(
        e.toString(),
        'GraphQL variables are not valid JSON: Unexpected character at 1:3',
      );
    });
  });
}

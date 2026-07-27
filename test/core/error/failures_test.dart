import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';

void main() {
  group('PersistenceFailure', () {
    test('equal for the same message (Equatable props)', () {
      expect(
        const PersistenceFailure('disk full'),
        const PersistenceFailure('disk full'),
      );
    });

    test('not equal for different messages', () {
      expect(
        const PersistenceFailure('disk full'),
        isNot(const PersistenceFailure('corrupt box')),
      );
    });

    test('is an Exception so it can cross a throw boundary', () {
      expect(const PersistenceFailure('x'), isA<Exception>());
    });
  });

  group('NetworkFailure', () {
    test('equal when message, type, and statusCode all match', () {
      expect(
        const NetworkFailure(
          'boom',
          type: NetworkFailureType.badResponse,
          statusCode: 500,
        ),
        const NetworkFailure(
          'boom',
          type: NetworkFailureType.badResponse,
          statusCode: 500,
        ),
      );
    });

    test('type participates in equality', () {
      expect(
        const NetworkFailure('boom', type: NetworkFailureType.sendTimeout),
        isNot(
          const NetworkFailure('boom', type: NetworkFailureType.cancelled),
        ),
      );
    });

    test('statusCode participates in equality (null vs set)', () {
      expect(
        const NetworkFailure('boom', type: NetworkFailureType.badResponse),
        isNot(
          const NetworkFailure(
            'boom',
            type: NetworkFailureType.badResponse,
            statusCode: 404,
          ),
        ),
      );
    });

    test('statusCode defaults to null', () {
      const failure = NetworkFailure(
        'boom',
        type: NetworkFailureType.unknown,
      );
      expect(failure.statusCode, isNull);
      expect(failure.message, 'boom');
    });
  });
}

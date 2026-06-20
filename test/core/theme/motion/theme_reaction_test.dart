import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

void main() {
  group('ThemeReaction.kindForStatus', () {
    test('2xx and 3xx are success', () {
      expect(ThemeReaction.kindForStatus(200), ThemeReactionKind.success);
      expect(ThemeReaction.kindForStatus(204), ThemeReactionKind.success);
      expect(ThemeReaction.kindForStatus(301), ThemeReactionKind.success);
      expect(ThemeReaction.kindForStatus(399), ThemeReactionKind.success);
    });
    test('4xx is clientError, 5xx is serverError', () {
      expect(ThemeReaction.kindForStatus(404), ThemeReactionKind.clientError);
      expect(ThemeReaction.kindForStatus(429), ThemeReactionKind.clientError);
      expect(ThemeReaction.kindForStatus(500), ThemeReactionKind.serverError);
      expect(ThemeReaction.kindForStatus(503), ThemeReactionKind.serverError);
    });
    test('0 / sub-200 / 6xx is networkError', () {
      expect(ThemeReaction.kindForStatus(0), ThemeReactionKind.networkError);
      expect(ThemeReaction.kindForStatus(100), ThemeReactionKind.networkError);
      expect(ThemeReaction.kindForStatus(600), ThemeReactionKind.networkError);
    });
  });

  test('isError true for the three error kinds only', () {
    bool err(ThemeReactionKind k) => ThemeReaction(kind: k).isError;
    expect(err(ThemeReactionKind.success), isFalse);
    expect(err(ThemeReactionKind.sendStarted), isFalse);
    expect(err(ThemeReactionKind.cancelled), isFalse);
    expect(err(ThemeReactionKind.clientError), isTrue);
    expect(err(ThemeReactionKind.serverError), isTrue);
    expect(err(ThemeReactionKind.networkError), isTrue);
  });

  test('value equality', () {
    expect(
      const ThemeReaction(
        kind: ThemeReactionKind.success,
        statusCode: 200,
        durationMs: 12,
      ),
      const ThemeReaction(
        kind: ThemeReactionKind.success,
        statusCode: 200,
        durationMs: 12,
      ),
    );
  });

  group('transportFailure field', () {
    test('defaults to null and is part of equality', () {
      const a = ThemeReaction(kind: ThemeReactionKind.networkError);
      expect(a.transportFailure, isNull);
      const b = ThemeReaction(
        kind: ThemeReactionKind.networkError,
        transportFailure: TransportFailureKind.timeout,
      );
      expect(a == b, isFalse);
      expect(b.transportFailure, TransportFailureKind.timeout);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

ThemeReaction _http(int code) => ThemeReaction(
  kind: ThemeReaction.kindForStatus(code),
  statusCode: code,
);

void main() {
  group('flavorFor — mapped status codes', () {
    const cases = {
      201: StatusReactionFlavor.created,
      204: StatusReactionFlavor.noContent,
      304: StatusReactionFlavor.notModified,
      401: StatusReactionFlavor.unauthorized,
      403: StatusReactionFlavor.forbidden,
      404: StatusReactionFlavor.notFound,
      408: StatusReactionFlavor.timeout,
      429: StatusReactionFlavor.rateLimited,
      500: StatusReactionFlavor.serverCrash,
      503: StatusReactionFlavor.serviceUnavailable,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test('$key => $value', () => expect(flavorFor(_http(key)), value));
    }
  });

  group('flavorFor — class fallbacks', () {
    test(
      '200 => ok',
      () => expect(flavorFor(_http(200)), StatusReactionFlavor.ok),
    );
    test(
      '301 => ok',
      () => expect(flavorFor(_http(301)), StatusReactionFlavor.ok),
    );
    test(
      '418 => clientError',
      () => expect(flavorFor(_http(418)), StatusReactionFlavor.clientError),
    );
    test(
      '502 => serverError',
      () => expect(flavorFor(_http(502)), StatusReactionFlavor.serverError),
    );
    test(
      '0 => networkError',
      () => expect(flavorFor(_http(0)), StatusReactionFlavor.networkError),
    );
  });

  group('flavorFor — non-HTTP kinds', () {
    test('cancelled', () {
      expect(
        flavorFor(const ThemeReaction(kind: ThemeReactionKind.cancelled)),
        StatusReactionFlavor.cancelled,
      );
    });
    test('networkError', () {
      expect(
        flavorFor(const ThemeReaction(kind: ThemeReactionKind.networkError)),
        StatusReactionFlavor.networkError,
      );
    });
    test('null statusCode on success kind falls back to ok', () {
      expect(
        flavorFor(const ThemeReaction(kind: ThemeReactionKind.success)),
        StatusReactionFlavor.ok,
      );
    });
  });

  group('flavorFor — transport failures', () {
    ThemeReaction net(TransportFailureKind? t) => ThemeReaction(
      kind: ThemeReactionKind.networkError,
      transportFailure: t,
    );
    test('timeout transport → timeout flavor', () {
      expect(
        flavorFor(net(TransportFailureKind.timeout)),
        StatusReactionFlavor.timeout,
      );
    });
    test('badCertificate transport → badCertificate flavor', () {
      expect(
        flavorFor(net(TransportFailureKind.badCertificate)),
        StatusReactionFlavor.badCertificate,
      );
    });
    test('null transport → networkError flavor', () {
      expect(flavorFor(net(null)), StatusReactionFlavor.networkError);
    });
  });
}

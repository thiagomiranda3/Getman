// Unit tests for dio_adapter_config_io.dart: the client-certificate failure
// signal (lastCertificateError + onCertificateError — a broken cert must
// never be dropped silently) and buildConfiguredHttpClient's verify-SSL /
// proxy / connect-timeout wiring for wss:// handshakes.

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/dio_adapter_config_io.dart';

void main() {
  group('client certificate failure signal', () {
    test(
      'a cert that fails to load records lastCertificateError and invokes '
      'onCertificateError instead of failing silently',
      () {
        final dio = Dio();
        final messages = <String>[];

        configureHttpAdapter(
          dio,
          verifySsl: true,
          clientCertPath: '/nonexistent/client.pem',
          clientKeyPath: '/nonexistent/client.key',
          onCertificateError: messages.add,
        );

        expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
        expect(lastCertificateError, isNotNull);
        expect(
          lastCertificateError,
          contains('Client certificate load failed'),
        );
        expect(messages, hasLength(1));
        expect(messages.single, lastCertificateError);
      },
    );

    test(
      'a configure without a cert clears a previously recorded error '
      '(removing the broken config resets the signal)',
      () {
        final dio = Dio();
        configureHttpAdapter(
          dio,
          verifySsl: true,
          clientCertPath: '/nonexistent/client.pem',
          clientKeyPath: '/nonexistent/client.key',
        );
        expect(lastCertificateError, isNotNull);

        configureHttpAdapter(dio, verifySsl: true);

        expect(lastCertificateError, isNull);
      },
    );

    test('a cert path without a key path is treated as not configured '
        '(no error, no callback)', () {
      final dio = Dio();
      final messages = <String>[];

      configureHttpAdapter(
        dio,
        verifySsl: true,
        clientCertPath: '/certs/client.pem',
        onCertificateError: messages.add,
      );

      expect(lastCertificateError, isNull);
      expect(messages, isEmpty);
    });

    test(
      'buildConfiguredHttpClient records the failure too and still returns '
      'a usable (cert-less) client',
      () {
        final messages = <String>[];

        final client = buildConfiguredHttpClient(
          verifySsl: true,
          clientCertPath: '/nonexistent/client.pem',
          clientKeyPath: '/nonexistent/client.key',
          onCertificateError: messages.add,
        );

        expect(lastCertificateError, isNotNull);
        expect(messages, hasLength(1));
        client.close(force: true);
      },
    );
  });

  group('buildConfiguredHttpClient', () {
    test('sets the socket connect timeout when positive', () {
      final client = buildConfiguredHttpClient(
        verifySsl: true,
        connectionTimeout: const Duration(seconds: 7),
      );

      expect(client.connectionTimeout, const Duration(seconds: 7));
      client.close(force: true);
    });

    test('leaves the connect timeout unset for zero/null (0 = disabled, '
        'matching the Dio timeout convention)', () {
      final zero = buildConfiguredHttpClient(
        verifySsl: true,
        connectionTimeout: Duration.zero,
      );
      final unset = buildConfiguredHttpClient(verifySsl: true);

      expect(zero.connectionTimeout, isNull);
      expect(unset.connectionTimeout, isNull);
      zero.close(force: true);
      unset.close(force: true);
    });
  });
}

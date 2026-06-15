import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockAddToHistoryUseCase extends Mock implements AddToHistoryUseCase {}

class MockGetSettingsUseCase extends Mock implements GetSettingsUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

void main() {
  late MockTabsRepository repository;
  late MockAddToHistoryUseCase addToHistory;
  late MockGetSettingsUseCase getSettings;
  late SendRequestUseCase useCase;

  const config = HttpRequestConfigEntity(
    id: 'c1',
    method: 'POST',
    url: 'https://{{host}}/login',
    body: '{"user":"{{user}}"}',
  );
  const envVars = {'host': 'api.dev', 'user': 'thiago'};
  const response = HttpResponseEntity(
    statusCode: 201,
    body: '{"token":"x"}',
    headers: {'content-type': 'application/json'},
    durationMs: 12,
  );

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
  });

  setUp(() {
    repository = MockTabsRepository();
    addToHistory = MockAddToHistoryUseCase();
    getSettings = MockGetSettingsUseCase();
    useCase = SendRequestUseCase(
      tabsRepository: repository,
      addToHistoryUseCase: addToHistory,
      getSettingsUseCase: getSettings,
    );
    when(
      () => getSettings.call(),
    ).thenAnswer((_) async => const SettingsEntity());
    when(() => addToHistory.call(any(), any())).thenAnswer((_) async {});
  });

  void stubSendSuccess() {
    when(
      () => repository.sendRequest(
        any(),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) async => response);
  }

  test('returns the repository response and records history', () async {
    stubSendSuccess();

    final result = await useCase(config: config, envVars: envVars);

    expect(result, response);
    verify(() => addToHistory.call(any(), any())).called(1);
  });

  test(
    'records the TEMPLATED config — env vars must never be resolved into '
    'history',
    () async {
      stubSendSuccess();

      await useCase(config: config, envVars: envVars);

      final recorded =
          verify(() => addToHistory.call(captureAny(), any())).captured.single
              as HttpRequestConfigEntity;
      expect(
        recorded.url,
        'https://{{host}}/login',
        reason:
            're-sending a history entry under a different environment must '
            'work',
      );
      expect(recorded.body, '{"user":"{{user}}"}');
    },
  );

  test('respects historyLimit from settings', () async {
    stubSendSuccess();
    when(
      () => getSettings.call(),
    ).thenAnswer((_) async => const SettingsEntity(historyLimit: 7));

    await useCase(config: config, envVars: envVars);

    verify(() => addToHistory.call(any(), 7)).called(1);
  });

  test(
    'snapshots the response into history only when saveResponseInHistory is on',
    () async {
      stubSendSuccess();
      when(() => getSettings.call()).thenAnswer(
        (_) async => const SettingsEntity(saveResponseInHistory: true),
      );

      await useCase(config: config, envVars: envVars);

      final recorded =
          verify(() => addToHistory.call(captureAny(), any())).captured.single
              as HttpRequestConfigEntity;
      expect(recorded.statusCode, 201);
      expect(recorded.responseBody, '{"token":"x"}');
    },
  );

  test(
    'omits the response snapshot when saveResponseInHistory is off',
    () async {
      stubSendSuccess();

      await useCase(config: config, envVars: envVars);

      final recorded =
          verify(() => addToHistory.call(captureAny(), any())).captured.single
              as HttpRequestConfigEntity;
      expect(recorded.statusCode, isNull);
      expect(recorded.responseBody, isNull);
    },
  );

  test('records failed requests and rethrows', () async {
    when(
      () => repository.sendRequest(
        any(),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenThrow(
      const NetworkFailure('boom', type: NetworkFailureType.connection),
    );

    await expectLater(
      () => useCase(config: config, envVars: envVars),
      throwsA(isA<NetworkFailure>()),
    );
    verify(() => addToHistory.call(any(), any())).called(1);
  });

  test(
    'records failed requests with saveResponseInHistory on '
    '(typed empty headers)',
    () async {
      // Regression: on the failure path `response` is null, so the recorded
      // config gets an empty header map. The fallback must be typed
      // (`Map<String, String>`) or copyWith's cast throws and history is
      // dropped.
      when(
        () => repository.sendRequest(
          any(),
          envVars: any(named: 'envVars'),
          cancelHandle: any(named: 'cancelHandle'),
        ),
      ).thenThrow(
        const NetworkFailure(
          'boom',
          type: NetworkFailureType.connection,
          statusCode: 500,
        ),
      );
      when(() => getSettings.call()).thenAnswer(
        (_) async => const SettingsEntity(saveResponseInHistory: true),
      );

      await expectLater(
        () => useCase(config: config, envVars: envVars),
        throwsA(isA<NetworkFailure>()),
      );

      final recorded =
          verify(() => addToHistory.call(captureAny(), any())).captured.single
              as HttpRequestConfigEntity;
      expect(recorded.statusCode, 500);
      expect(recorded.responseBody, 'boom');
      expect(recorded.responseHeaders, isEmpty);
    },
  );

  test('does NOT record cancelled requests', () async {
    when(
      () => repository.sendRequest(
        any(),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenThrow(
      const NetworkFailure('cancelled', type: NetworkFailureType.cancelled),
    );

    await expectLater(
      () => useCase(config: config, envVars: envVars),
      throwsA(isA<NetworkFailure>()),
    );
    verifyNever(() => addToHistory.call(any(), any()));
  });

  test('a history write failure never fails the request', () async {
    stubSendSuccess();
    when(
      () => addToHistory.call(any(), any()),
    ).thenThrow(const PersistenceFailure('disk full'));

    final result = await useCase(config: config, envVars: envVars);

    expect(result, response);
  });

  group('response body cap (6c)', () {
    test('response body within limit is stored verbatim', () async {
      const smallBody = '{"ok":true}';
      when(
        () => repository.sendRequest(
          any(),
          envVars: any(named: 'envVars'),
          cancelHandle: any(named: 'cancelHandle'),
        ),
      ).thenAnswer(
        (_) async => const HttpResponseEntity(
          statusCode: 200,
          body: smallBody,
          headers: {},
          durationMs: 5,
        ),
      );
      when(() => getSettings.call()).thenAnswer(
        (_) async => const SettingsEntity(saveResponseInHistory: true),
      );

      await useCase(config: config, envVars: envVars);

      final recorded =
          verify(() => addToHistory.call(captureAny(), any())).captured.single
              as HttpRequestConfigEntity;
      expect(recorded.responseBody, smallBody);
    });

    test('response body over limit is replaced with the placeholder', () async {
      // Build a body that exceeds kMaxPersistedResponseBodyChars.
      final largeBody = 'x' * (kMaxPersistedResponseBodyChars + 1);
      when(
        () => repository.sendRequest(
          any(),
          envVars: any(named: 'envVars'),
          cancelHandle: any(named: 'cancelHandle'),
        ),
      ).thenAnswer(
        (_) async => HttpResponseEntity(
          statusCode: 200,
          body: largeBody,
          headers: const {},
          durationMs: 5,
        ),
      );
      when(() => getSettings.call()).thenAnswer(
        (_) async => const SettingsEntity(saveResponseInHistory: true),
      );

      await useCase(config: config, envVars: envVars);

      final recorded =
          verify(() => addToHistory.call(captureAny(), any())).captured.single
              as HttpRequestConfigEntity;
      expect(recorded.responseBody, kResponseBodyTooLargePlaceholder);
    });
  });
}

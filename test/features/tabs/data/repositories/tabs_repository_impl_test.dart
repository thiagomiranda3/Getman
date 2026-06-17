import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/repositories/tabs_repository_impl.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsLocalDataSource extends Mock implements TabsLocalDataSource {}

class MockNetworkService extends Mock implements NetworkService {}

void main() {
  late MockTabsLocalDataSource dataSource;
  late MockNetworkService networkService;
  late TabsRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(
      HttpRequestTabModel(
        config: HttpRequestConfig(id: 'fallback'),
        tabId: 'fallback',
      ),
    );
  });

  setUp(() {
    dataSource = MockTabsLocalDataSource();
    networkService = MockNetworkService();
    repository = TabsRepositoryImpl(
      localDataSource: dataSource,
      networkService: networkService,
    );
  });

  HttpRequestTabEntity tabWithBody(String body) => HttpRequestTabEntity(
    tabId: 't',
    config: const HttpRequestConfigEntity(id: 't', url: 'https://t.dev'),
    response: HttpResponseEntity(
      statusCode: 200,
      body: body,
      headers: const {'content-type': 'application/json'},
      durationMs: 42,
    ),
  );

  group('response-body persistence cap', () {
    test('putTab replaces an over-limit body with the placeholder', () async {
      when(() => dataSource.putTab(any())).thenAnswer((_) async {});
      final tab = tabWithBody('x' * (kMaxPersistedResponseBodyChars + 1));

      await repository.putTab(tab);

      final model =
          verify(() => dataSource.putTab(captureAny())).captured.single
              as HttpRequestTabModel;
      expect(model.responseBody, kResponseBodyTooLargePlaceholder);
      // Status, headers and duration survive the cap.
      expect(model.statusCode, 200);
      expect(model.responseHeaders, {'content-type': 'application/json'});
      expect(model.durationMs, 42);
    });

    test('putTab keeps a body at the limit verbatim', () async {
      when(() => dataSource.putTab(any())).thenAnswer((_) async {});
      final body = 'x' * kMaxPersistedResponseBodyChars;

      await repository.putTab(tabWithBody(body));

      final model =
          verify(() => dataSource.putTab(captureAny())).captured.single
              as HttpRequestTabModel;
      expect(model.responseBody, body);
    });

    test('putTab passes tabs without a response through untouched', () async {
      when(() => dataSource.putTab(any())).thenAnswer((_) async {});
      const tab = HttpRequestTabEntity(
        tabId: 't',
        config: HttpRequestConfigEntity(id: 't'),
      );

      await repository.putTab(tab);

      final model =
          verify(() => dataSource.putTab(captureAny())).captured.single
              as HttpRequestTabModel;
      expect(model.responseBody, isNull);
      expect(model.statusCode, isNull);
    });

    test('saveTabs applies the same cap to every tab', () async {
      when(() => dataSource.saveTabs(any())).thenAnswer((_) async {});
      final tab = tabWithBody('x' * (kMaxPersistedResponseBodyChars + 1));

      await repository.saveTabs([tab]);

      final models =
          verify(() => dataSource.saveTabs(captureAny())).captured.single
              as List<HttpRequestTabModel>;
      expect(models.single.responseBody, kResponseBodyTooLargePlaceholder);
    });

    test('putTab caps over-limit bodies in history entries too', () async {
      when(() => dataSource.putTab(any())).thenAnswer((_) async {});
      final tab = HttpRequestTabEntity(
        tabId: 't',
        config: const HttpRequestConfigEntity(id: 't'),
        response: const HttpResponseEntity(
          statusCode: 200,
          body: 'small',
          headers: {},
          durationMs: 1,
        ),
        responseHistory: [
          ResponseHistoryEntry(
            id: 'e1',
            response: HttpResponseEntity(
              statusCode: 200,
              body: 'x' * (kMaxPersistedResponseBodyChars + 1),
              headers: const {},
              durationMs: 1,
            ),
            capturedAt: 1,
          ),
        ],
      );

      await repository.putTab(tab);

      final model =
          verify(() => dataSource.putTab(captureAny())).captured.single
              as HttpRequestTabModel;
      expect(model.responseBody, 'small');
      expect(
        model.responseHistory!.single.body,
        kResponseBodyTooLargePlaceholder,
      );
      // Metadata on the capped history entry survives.
      expect(model.responseHistory!.single.statusCode, 200);
      expect(model.responseHistory!.single.id, 'e1');
    });
  });

  group('sendRequest auth injection', () {
    const response = HttpResponseEntity(
      statusCode: 200,
      body: '',
      headers: {},
      durationMs: 1,
    );

    void stubRequest() {
      when(
        () => networkService.request(
          url: any(named: 'url'),
          method: any(named: 'method'),
          queryParameters: any(named: 'queryParameters'),
          data: any<dynamic>(named: 'data'),
          headers: any(named: 'headers'),
          cancelHandle: any(named: 'cancelHandle'),
        ),
      ).thenAnswer((_) async => response);
    }

    Map<String, dynamic> capturedHeaders() {
      return verify(
            () => networkService.request(
              url: any(named: 'url'),
              method: any(named: 'method'),
              queryParameters: any(named: 'queryParameters'),
              data: any<dynamic>(named: 'data'),
              headers: captureAny(named: 'headers'),
              cancelHandle: any(named: 'cancelHandle'),
            ),
          ).captured.single
          as Map<String, dynamic>;
    }

    test('injects a Bearer Authorization header, resolving env vars', () async {
      stubRequest();
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        auth: {'type': 'bearer', 'token': '{{tok}}'},
      );

      await repository.sendRequest(config, envVars: {'tok': 'secret'});

      expect(capturedHeaders()['Authorization'], 'Bearer secret');
    });

    test('does not inject auth when config.auth is empty', () async {
      stubRequest();
      const config = HttpRequestConfigEntity(id: 'c', url: 'https://api.dev/x');

      await repository.sendRequest(config);

      expect(capturedHeaders().containsKey('Authorization'), isFalse);
    });

    test('api-key in query rides through to queryParameters', () async {
      stubRequest();
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        auth: {
          'type': 'apikey',
          'key': 'api_key',
          'value': 'v',
          'addTo': 'query',
        },
      );

      await repository.sendRequest(config);

      final query =
          verify(
                () => networkService.request(
                  url: any(named: 'url'),
                  method: any(named: 'method'),
                  queryParameters: captureAny(named: 'queryParameters'),
                  data: any<dynamic>(named: 'data'),
                  headers: any(named: 'headers'),
                  cancelHandle: any(named: 'cancelHandle'),
                ),
              ).captured.single
              as Map<String, List<String>>;
      expect(query['api_key'], ['v']);
    });
  });

  group('sendRequest body assembly failures', () {
    test(
      'a multipart body with a missing file fails as NetworkFailure, '
      'not FileSystemException',
      () async {
        const config = HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.dev/upload',
          bodyType: BodyType.multipart,
          formFields: [
            MultipartFieldEntity(
              name: 'file',
              isFile: true,
              filePath: '/no/such/getman_missing_file_xyz.bin',
            ),
          ],
        );

        await expectLater(
          () => repository.sendRequest(config),
          throwsA(
            isA<NetworkFailure>().having((f) => f.statusCode, 'statusCode', 0),
          ),
        );
        verifyNever(
          () => networkService.request(
            url: any(named: 'url'),
            method: any(named: 'method'),
            queryParameters: any(named: 'queryParameters'),
            data: any<dynamic>(named: 'data'),
            headers: any(named: 'headers'),
            cancelHandle: any(named: 'cancelHandle'),
          ),
        );
      },
    );
  });

  group('forwarding and failure translation', () {
    test('deleteTabs and saveTabOrder forward to the data source', () async {
      when(() => dataSource.deleteTabs(any())).thenAnswer((_) async {});
      when(() => dataSource.saveOrder(any())).thenAnswer((_) async {});

      await repository.deleteTabs(['a', 'b']);
      await repository.saveTabOrder(['b']);

      verify(() => dataSource.deleteTabs(['a', 'b'])).called(1);
      verify(() => dataSource.saveOrder(['b'])).called(1);
    });

    test('translates PersistenceException into PersistenceFailure', () async {
      when(
        () => dataSource.putTab(any()),
      ).thenThrow(PersistenceException('boom'));
      when(
        () => dataSource.deleteTabs(any()),
      ).thenThrow(PersistenceException('boom'));
      when(
        () => dataSource.saveOrder(any()),
      ).thenThrow(PersistenceException('boom'));

      expect(
        () => repository.putTab(tabWithBody('x')),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(
        () => repository.deleteTabs(['a']),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(
        () => repository.saveTabOrder(['a']),
        throwsA(isA<PersistenceFailure>()),
      );
    });
  });
}

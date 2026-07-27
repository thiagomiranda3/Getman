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
import 'package:getman/features/tabs/data/models/panel_model.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/repositories/tabs_repository_impl.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
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
    registerFallbackValue(
      PanelModel(
        id: 'fallback',
        name: 'fallback',
        orderedTabIds: const [],
        activeTabId: '',
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

  group('sendRequest disabled headers (B1)', () {
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

    test('headers in disabledHeaderKeys never reach the wire', () async {
      stubRequest();
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        headers: {'X-Keep': 'yes', 'X-Skip': 'no'},
        disabledHeaderKeys: {'X-Skip'},
      );

      await repository.sendRequest(config);

      final headers = capturedHeaders();
      expect(headers['X-Keep'], 'yes');
      expect(headers.containsKey('X-Skip'), isFalse);
    });

    test(
      'a disabled Authorization header does not block auth injection',
      () async {
        stubRequest();
        const config = HttpRequestConfigEntity(
          id: 'c',
          url: 'https://api.dev/x',
          headers: {'Authorization': 'manual-old'},
          disabledHeaderKeys: {'Authorization'},
          auth: {'type': 'bearer', 'token': 'abc'},
        );

        await repository.sendRequest(config);

        expect(
          capturedHeaders()['Authorization'],
          'Bearer abc',
          reason:
              'the disabled manual header is gone, so skip-if-set '
              'must not suppress the AUTH tab value',
        );
      },
    );
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

  group('tab and panel read/write forwarding', () {
    test('getTabs maps stored models to entities in order', () async {
      when(() => dataSource.getTabs()).thenAnswer(
        (_) async => [
          HttpRequestTabModel(
            config: HttpRequestConfig.fromEntity(
              const HttpRequestConfigEntity(id: 'c1', url: 'https://one.dev'),
            ),
            tabId: 't1',
          ),
          HttpRequestTabModel(
            config: HttpRequestConfig.fromEntity(
              const HttpRequestConfigEntity(id: 'c2', url: 'https://two.dev'),
            ),
            tabId: 't2',
          ),
        ],
      );

      final tabs = await repository.getTabs();

      expect(tabs.map((t) => t.tabId), ['t1', 't2']);
      expect(tabs.first.config.url, 'https://one.dev');
      expect(tabs.last.config.url, 'https://two.dev');
    });

    test('getActivePanelId forwards the stored id', () async {
      when(() => dataSource.getActivePanelId()).thenAnswer((_) async => 'p9');

      expect(await repository.getActivePanelId(), 'p9');
    });

    test('putPanel maps the entity (tabs → ordered tab ids)', () async {
      when(() => dataSource.putPanel(any())).thenAnswer((_) async {});
      const panel = PanelEntity(
        id: 'p1',
        name: 'Work',
        tabs: [
          HttpRequestTabEntity(
            tabId: 't1',
            config: HttpRequestConfigEntity(id: 'c1'),
          ),
          HttpRequestTabEntity(
            tabId: 't2',
            config: HttpRequestConfigEntity(id: 'c2'),
          ),
        ],
        activeTabId: 't2',
      );

      await repository.putPanel(panel);

      final model =
          verify(() => dataSource.putPanel(captureAny())).captured.single
              as PanelModel;
      expect(model.id, 'p1');
      expect(model.name, 'Work');
      expect(model.orderedTabIds, ['t1', 't2']);
      expect(model.activeTabId, 't2');
    });

    test('deletePanels and savePanelMeta forward verbatim', () async {
      when(() => dataSource.deletePanels(any())).thenAnswer((_) async {});
      when(
        () => dataSource.savePanelMeta(any(), any()),
      ).thenAnswer((_) async {});

      await repository.deletePanels(['p1', 'p2']);
      await repository.savePanelMeta(['p2', 'p1'], 'p2');

      verify(() => dataSource.deletePanels(['p1', 'p2'])).called(1);
      verify(() => dataSource.savePanelMeta(['p2', 'p1'], 'p2')).called(1);
    });

    test('panel operations translate PersistenceException into '
        'PersistenceFailure', () async {
      when(
        () => dataSource.getActivePanelId(),
      ).thenThrow(PersistenceException('boom'));
      when(
        () => dataSource.deletePanels(any()),
      ).thenThrow(PersistenceException('boom'));

      expect(
        () => repository.getActivePanelId(),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(
        () => repository.deletePanels(['p1']),
        throwsA(isA<PersistenceFailure>()),
      );
    });
  });

  group('sendRequest GraphQL variables', () {
    test(
      'invalid variables JSON fails as a status-0 NetworkFailure '
      'and never reaches the network',
      () async {
        const config = HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.dev/graphql',
          bodyType: BodyType.graphql,
          body: 'query { me { id } }',
          graphqlVariables: '{not valid json',
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

  group('sendRequest query assembly', () {
    test(
      'duplicate query keys ride through as list values, env-resolved',
      () async {
        when(
          () => networkService.request(
            url: any(named: 'url'),
            method: any(named: 'method'),
            queryParameters: any(named: 'queryParameters'),
            data: any<dynamic>(named: 'data'),
            headers: any(named: 'headers'),
            cancelHandle: any(named: 'cancelHandle'),
          ),
        ).thenAnswer(
          (_) async => const HttpResponseEntity(
            statusCode: 200,
            body: '',
            headers: {},
            durationMs: 1,
          ),
        );
        const config = HttpRequestConfigEntity(
          id: 'c',
          url: 'https://{{host}}/x?k=1&k=2&env={{v}}',
        );

        await repository.sendRequest(
          config,
          envVars: {'host': 'api.dev', 'v': 'resolved'},
        );

        final captured = verify(
          () => networkService.request(
            url: captureAny(named: 'url'),
            method: any(named: 'method'),
            queryParameters: captureAny(named: 'queryParameters'),
            data: any<dynamic>(named: 'data'),
            headers: any(named: 'headers'),
            cancelHandle: any(named: 'cancelHandle'),
          ),
        ).captured;
        expect(captured.first, 'https://api.dev/x');
        expect(captured.last, {
          'k': ['1', '2'],
          'env': ['resolved'],
        });
      },
    );
  });
}

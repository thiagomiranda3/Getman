import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/cookie_interceptor.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockDio extends Mock implements Dio {}

class _CloseSpyAdapter implements HttpClientAdapter {
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(const [], 200);

  @override
  void close({bool force = false}) => closed = true;
}

class _MockWsChannel extends Mock implements WebSocketChannel {}

class _MockWsSink extends Mock implements WebSocketSink {}

class _FakeCookieStore implements CookieStore {
  String? header;

  @override
  String? cookieHeaderFor(Uri uri) => header;
  @override
  void storeFromSetCookie(Uri requestUri, String setCookieHeader) {}
  @override
  List<NetworkCookie> all() => const [];
  @override
  Future<void> remove(NetworkCookie cookie) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('SSE', () {
    test(
      'the open frame reaches a listener that subscribes after construction',
      () async {
        final body = StreamController<Uint8List>();
        final dio = _MockDio();
        when(
          () => dio.get<ResponseBody>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<ResponseBody>(
            data: ResponseBody(body.stream, 200),
            requestOptions: RequestOptions(path: '/'),
          ),
        );

        // The bloc subscribes right AFTER connectSse returns — the open frame
        // must not be lost to the unbuffered broadcast controller.
        final conn = RealtimeService(
          dio: dio,
        ).connectSse('https://api.dev/events');
        final frames = <RealtimeFrame>[];
        conn.frames.listen(frames.add);
        await Future<void>.delayed(Duration.zero);

        expect(frames, isNotEmpty);
        expect(frames.first.direction, RealtimeDirection.open);
        expect(frames.first.text, contains('https://api.dev/events'));
        await body.close();
      },
    );

    test(
      'emits an incoming frame per event and a close frame on done',
      () async {
        final body = StreamController<Uint8List>();
        final dio = _MockDio();
        when(
          () => dio.get<ResponseBody>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<ResponseBody>(
            data: ResponseBody(body.stream, 200),
            requestOptions: RequestOptions(path: '/'),
          ),
        );

        final conn = RealtimeService(
          dio: dio,
        ).connectSse('https://api.dev/events');
        final frames = <RealtimeFrame>[];
        conn.frames.listen(frames.add);

        await Future<void>.delayed(
          Duration.zero,
        ); // let dio.get().then() attach the listener
        body.add(Uint8List.fromList(utf8.encode('data: hello\n\n')));
        await Future<void>.delayed(Duration.zero);
        await body.close();
        await Future<void>.delayed(Duration.zero);

        final incoming = frames
            .where((f) => f.direction == RealtimeDirection.incoming)
            .map((f) => f.text);
        expect(incoming, contains('hello'));
        expect(frames.last.direction, RealtimeDirection.close);
      },
    );

    test(
      'a non-2xx response emits an error + close frame instead of parsing '
      'the stream',
      () async {
        final body = StreamController<Uint8List>();
        final dio = _MockDio();
        when(
          () => dio.get<ResponseBody>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<ResponseBody>(
            data: ResponseBody(body.stream, 404),
            statusCode: 404,
            statusMessage: 'Not Found',
            requestOptions: RequestOptions(path: '/'),
          ),
        );

        final conn = RealtimeService(
          dio: dio,
        ).connectSse('https://api.dev/events');
        final frames = <RealtimeFrame>[];
        conn.frames.listen(frames.add);
        await Future<void>.delayed(Duration.zero);

        expect(
          frames
              .where((f) => f.direction == RealtimeDirection.error)
              .map((f) => f.text),
          contains('HTTP 404 Not Found'),
        );
        expect(frames.last.direction, RealtimeDirection.close);

        // The stream must never have been parsed for events.
        body.add(Uint8List.fromList(utf8.encode('data: nope\n\n')));
        await Future<void>.delayed(Duration.zero);
        expect(frames.any((f) => f.text.contains('nope')), isFalse);

        // Deliberately not awaited: it was never listened to (the fix
        // returns before subscribing), and a single-subscription
        // StreamController's `close()` future only resolves once a listener
        // has drained it — awaiting it here would hang the test.
        unawaited(body.close());
      },
    );

    test('close cancels the request before the response resolves', () async {
      CancelToken? captured;
      final dio = _MockDio();
      when(
        () => dio.get<ResponseBody>(
          any(),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        captured = invocation.namedArguments[#cancelToken] as CancelToken?;
        // Never completes with data — simulate an open stream.
        return Response<ResponseBody>(
          data: ResponseBody(const Stream<Uint8List>.empty(), 200),
          requestOptions: RequestOptions(path: '/'),
        );
      });

      final conn = RealtimeService(
        dio: dio,
      ).connectSse('https://api.dev/events');
      await conn.close();

      expect(captured, isNotNull);
      expect(captured!.isCancelled, isTrue);
    });
  });

  group('SSE Dio wiring (network settings + cookies)', () {
    test('buildSseDio sets stream/validateStatus options', () {
      final dio = RealtimeService.buildSseDio(NetworkConfig.defaults);

      expect(dio.options.responseType, ResponseType.stream);
      expect(dio.options.validateStatus(404), isTrue);
      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
    });

    test('buildSseDio adds the given cookie interceptor', () {
      final store = _FakeCookieStore()..header = 'sid=abc';
      final interceptor = CookieInterceptor(store);

      final dio = RealtimeService.buildSseDio(
        NetworkConfig.defaults,
        interceptor,
      );

      expect(dio.interceptors, contains(interceptor));
      // Prove it is actually wired, not just appended: it must add the jar's
      // cookie header to an outgoing request.
      final options = RequestOptions(path: 'https://api.dev/events');
      dio.interceptors.whereType<CookieInterceptor>().single.onRequest(
        options,
        RequestInterceptorHandler(),
      );
      expect(options.headers['Cookie'], 'sid=abc');
    });

    test(
      'applyConfig reconfigures the adapter and preserves interceptors',
      () {
        final store = _FakeCookieStore();
        final interceptor = CookieInterceptor(store);
        final dio = RealtimeService.buildSseDio(
          NetworkConfig.defaults,
          interceptor,
        );
        final service = RealtimeService(dio: dio);
        final firstAdapter = dio.httpClientAdapter;

        service.applyConfig(
          const NetworkConfig(verifySsl: false, proxyUrl: 'localhost:8080'),
        );

        expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
        expect(dio.httpClientAdapter, isNot(same(firstAdapter)));
        expect(dio.interceptors, contains(interceptor));
      },
    );

    test('applyConfig with unchanged adapter fields keeps the adapter', () {
      final dio = RealtimeService.buildSseDio(NetworkConfig.defaults);
      final service = RealtimeService(dio: dio)
        ..applyConfig(const NetworkConfig(proxyUrl: 'p:1'));
      final adapter = dio.httpClientAdapter;

      service.applyConfig(const NetworkConfig(proxyUrl: 'p:1'));

      expect(dio.httpClientAdapter, same(adapter));
    });

    test('applyConfig closes the replaced adapter on a proxy change', () {
      final dio = RealtimeService.buildSseDio(NetworkConfig.defaults);
      final service = RealtimeService(dio: dio)
        ..applyConfig(const NetworkConfig(proxyUrl: 'a:1'));
      final spy = _CloseSpyAdapter();
      dio.httpClientAdapter = spy;

      service.applyConfig(const NetworkConfig(proxyUrl: 'b:2'));

      expect(spy.closed, isTrue);
      expect(dio.httpClientAdapter, isNot(same(spy)));
    });
  });

  group('WebSocket', () {
    test('emits incoming frames and closes the sink on close', () async {
      final incoming = StreamController<dynamic>();
      final sink = _MockWsSink();
      final channel = _MockWsChannel();
      when(() => channel.stream).thenAnswer((_) => incoming.stream);
      when(() => channel.sink).thenReturn(sink);
      when(sink.close).thenAnswer((_) async {});

      final conn = RealtimeService(
        webSocketFactory: (_) => channel,
      ).connectWebSocket('wss://api.dev/socket');
      final frames = <RealtimeFrame>[];
      conn.frames.listen(frames.add);

      incoming.add('pong');
      await Future<void>.delayed(Duration.zero);

      expect(
        frames
            .where((f) => f.direction == RealtimeDirection.incoming)
            .map((f) => f.text),
        ['pong'],
      );

      await conn.close();
      verify(sink.close).called(1);
      await incoming.close();
    });

    test(
      'the open frame reaches a listener that subscribes after construction',
      () async {
        final incoming = StreamController<dynamic>();
        final sink = _MockWsSink();
        final channel = _MockWsChannel();
        when(() => channel.stream).thenAnswer((_) => incoming.stream);
        when(() => channel.sink).thenReturn(sink);
        when(sink.close).thenAnswer((_) async {});

        final conn = RealtimeService(
          webSocketFactory: (_) => channel,
        ).connectWebSocket('wss://api.dev/socket');
        final frames = <RealtimeFrame>[];
        conn.frames.listen(frames.add);
        await Future<void>.delayed(Duration.zero);

        expect(frames, isNotEmpty);
        expect(frames.first.direction, RealtimeDirection.open);
        await conn.close();
        await incoming.close();
      },
    );

    test(
      'a binary frame is rendered as a compact byte-count placeholder, not a '
      'raw Dart list dump',
      () async {
        final incoming = StreamController<dynamic>();
        final sink = _MockWsSink();
        final channel = _MockWsChannel();
        when(() => channel.stream).thenAnswer((_) => incoming.stream);
        when(() => channel.sink).thenReturn(sink);
        when(sink.close).thenAnswer((_) async {});

        final conn = RealtimeService(
          webSocketFactory: (_) => channel,
        ).connectWebSocket('wss://api.dev/socket');
        final frames = <RealtimeFrame>[];
        conn.frames.listen(frames.add);

        incoming.add(Uint8List.fromList(List.filled(1024, 42)));
        await Future<void>.delayed(Duration.zero);

        final incomingFrames = frames.where(
          (f) => f.direction == RealtimeDirection.incoming,
        );
        expect(incomingFrames.single.text, '[binary frame · 1024 bytes]');

        await conn.close();
        await incoming.close();
      },
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockDio extends Mock implements Dio {}

class _MockWsChannel extends Mock implements WebSocketChannel {}

class _MockWsSink extends Mock implements WebSocketSink {}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('SSE', () {
    test('emits an incoming frame per event and a close frame on done', () async {
      final body = StreamController<Uint8List>();
      final dio = _MockDio();
      when(() => dio.get<ResponseBody>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Response<ResponseBody>(
            data: ResponseBody(body.stream, 200),
            requestOptions: RequestOptions(path: '/'),
          ));

      final conn = RealtimeService(dio: dio).connectSse('https://api.dev/events');
      final frames = <RealtimeFrame>[];
      conn.frames.listen(frames.add);

      await Future<void>.delayed(Duration.zero); // let dio.get().then() attach the listener
      body.add(Uint8List.fromList(utf8.encode('data: hello\n\n')));
      await Future<void>.delayed(Duration.zero);
      await body.close();
      await Future<void>.delayed(Duration.zero);

      final incoming = frames.where((f) => f.direction == RealtimeDirection.incoming).map((f) => f.text);
      expect(incoming, contains('hello'));
      expect(frames.last.direction, RealtimeDirection.close);
    });

    test('close cancels the request before the response resolves', () async {
      CancelToken? captured;
      final dio = _MockDio();
      when(() => dio.get<ResponseBody>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((invocation) async {
        captured = invocation.namedArguments[#cancelToken] as CancelToken?;
        // Never completes with data — simulate an open stream.
        return Response<ResponseBody>(
          data: ResponseBody(const Stream<Uint8List>.empty(), 200),
          requestOptions: RequestOptions(path: '/'),
        );
      });

      final conn = RealtimeService(dio: dio).connectSse('https://api.dev/events');
      await conn.close();

      expect(captured, isNotNull);
      expect(captured!.isCancelled, isTrue);
    });
  });

  group('WebSocket', () {
    test('emits incoming frames and closes the sink on close', () async {
      final incoming = StreamController<dynamic>();
      final sink = _MockWsSink();
      final channel = _MockWsChannel();
      when(() => channel.stream).thenAnswer((_) => incoming.stream);
      when(() => channel.sink).thenReturn(sink);
      when(() => sink.close()).thenAnswer((_) async {});

      final conn = RealtimeService(webSocketFactory: (_) => channel)
          .connectWebSocket('wss://api.dev/socket');
      final frames = <RealtimeFrame>[];
      conn.frames.listen(frames.add);

      incoming.add('pong');
      await Future<void>.delayed(Duration.zero);

      expect(
        frames.where((f) => f.direction == RealtimeDirection.incoming).map((f) => f.text),
        ['pong'],
      );

      await conn.close();
      verify(() => sink.close()).called(1);
      await incoming.close();
    });
  });
}

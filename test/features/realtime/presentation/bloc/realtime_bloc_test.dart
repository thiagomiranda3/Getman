import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:mocktail/mocktail.dart';

class MockRealtimeService extends Mock implements RealtimeService {}

class _FakeConnection implements RealtimeConnection {
  final controller = StreamController<RealtimeFrame>.broadcast();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<RealtimeFrame> get frames => controller.stream;

  @override
  void send(String message) {
    sent.add(message);
    controller.add(RealtimeFrame.outgoing(message));
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  late MockRealtimeService service;
  late RealtimeBloc bloc;
  late _FakeConnection fake;

  setUp(() {
    service = MockRealtimeService();
    fake = _FakeConnection();
    when(() => service.connectWebSocket(any())).thenReturn(fake);
    bloc = RealtimeBloc(service: service);
  });

  tearDown(() => bloc.close());

  Future<void> connect() async {
    bloc.add(const Connect(tabId: 't1', kind: RequestKind.webSocket, url: 'wss://x'));
    await bloc.stream.firstWhere((s) => s.sessionFor('t1').connected);
  }

  test('Connect opens a WebSocket session', () async {
    await connect();
    expect(bloc.state.sessionFor('t1').connected, isTrue);
    verify(() => service.connectWebSocket('wss://x')).called(1);
  });

  test('incoming frames are appended to the session log', () async {
    await connect();
    fake.controller.add(RealtimeFrame.incoming('hello'));
    await bloc.stream.firstWhere((s) => s.sessionFor('t1').frames.any((f) => f.text == 'hello'));
    expect(bloc.state.sessionFor('t1').frames.last.text, 'hello');
  });

  test('SendRealtimeMessage forwards to the connection', () async {
    await connect();
    bloc.add(const SendRealtimeMessage('t1', 'ping'));
    await bloc.stream.firstWhere(
        (s) => s.sessionFor('t1').frames.any((f) => f.direction == RealtimeDirection.outgoing));
    expect(fake.sent, ['ping']);
  });

  test('Disconnect closes the connection and marks disconnected', () async {
    await connect();
    bloc.add(const Disconnect('t1'));
    await bloc.stream.firstWhere((s) => !s.sessionFor('t1').connected);
    expect(fake.closed, isTrue);
  });

  test('a close frame marks the session disconnected', () async {
    await connect();
    fake.controller.add(RealtimeFrame.close());
    await bloc.stream.firstWhere((s) => !s.sessionFor('t1').connected);
    expect(bloc.state.sessionFor('t1').connected, isFalse);
  });
}

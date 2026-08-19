import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:mocktail/mocktail.dart';

class MockRealtimeService extends Mock implements RealtimeService {}

class _FakeConnection implements RealtimeConnection {
  final controller = StreamController<RealtimeFrame>.broadcast();
  final sent = <String>[];
  bool closed = false;

  /// When set, [close] waits on it before completing — lets tests hold a
  /// teardown open while other handlers keep running.
  Completer<void>? closeGate;

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
    final gate = closeGate;
    if (gate != null) await gate.future;
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
    bloc.add(
      const Connect(tabId: 't1', kind: RequestKind.webSocket, url: 'wss://x'),
    );
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
    await bloc.stream.firstWhere(
      (s) => s.sessionFor('t1').frames.any((f) => f.text == 'hello'),
    );
    expect(bloc.state.sessionFor('t1').frames.last.text, 'hello');
  });

  test('SendRealtimeMessage forwards to the connection', () async {
    await connect();
    bloc.add(const SendRealtimeMessage('t1', 'ping'));
    await bloc.stream.firstWhere(
      (s) => s
          .sessionFor('t1')
          .frames
          .any((f) => f.direction == RealtimeDirection.outgoing),
    );
    expect(fake.sent, ['ping']);
  });

  test('Disconnect closes the connection and marks disconnected', () async {
    await connect();
    bloc.add(const Disconnect('t1'));
    await bloc.stream.firstWhere((s) => !s.sessionFor('t1').connected);
    expect(fake.closed, isTrue);
  });

  test(
    'RealtimeTabsClosed closes the connection and drops the session entry',
    () async {
      await connect();
      expect(bloc.state.sessions.containsKey('t1'), isTrue);

      bloc.add(const RealtimeTabsClosed({'t1'}));
      await bloc.stream.firstWhere((s) => !s.sessions.containsKey('t1'));

      expect(fake.closed, isTrue);
      expect(
        bloc.state.sessions.containsKey('t1'),
        isFalse,
        reason:
            'a closed tab has nothing left to show a session for — the '
            'entry is dropped entirely, not merely marked disconnected',
      );
    },
  );

  test('RealtimeTabsClosed for an id with no session emits nothing', () async {
    await connect();
    final emissions = <RealtimeState>[];
    final sub = bloc.stream.listen(emissions.add);

    bloc.add(const RealtimeTabsClosed({'ghost'}));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();

    expect(emissions, isEmpty, reason: 'no session to drop, no emission');
    expect(bloc.state.sessions.keys.toList(), ['t1']);
    expect(fake.closed, isFalse);
  });

  test('a close frame marks the session disconnected', () async {
    await connect();
    fake.controller.add(RealtimeFrame.close());
    await bloc.stream.firstWhere((s) => !s.sessionFor('t1').connected);
    expect(bloc.state.sessionFor('t1').connected, isFalse);
  });

  test(
    'coalesces a burst of frames into far fewer state emissions, in order',
    () async {
      await connect();
      final emissions = <int>[];
      final sub = bloc.stream.listen(
        (s) => emissions.add(s.sessionFor('t1').frames.length),
      );

      for (var i = 0; i < 20; i++) {
        fake.controller.add(RealtimeFrame.incoming('m$i'));
      }
      await bloc.stream.firstWhere(
        (s) => s.sessionFor('t1').frames.length == 20,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(
        bloc.state.sessionFor('t1').frames.map((f) => f.text).toList(),
        List.generate(20, (i) => 'm$i'),
        reason: 'all frames preserved in arrival order',
      );
      expect(
        emissions.length,
        lessThan(20),
        reason:
            'a synchronous burst collapses to far fewer emissions than frames',
      );
    },
  );

  test('enforces the 500-frame cap, keeping the newest', () async {
    await connect();
    for (var i = 0; i < 600; i++) {
      fake.controller.add(RealtimeFrame.incoming('m$i'));
    }
    await bloc.stream.firstWhere(
      (s) => s.sessionFor('t1').frames.length >= 500,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final frames = bloc.state.sessionFor('t1').frames;
    expect(frames.length, 500);
    expect(frames.last.text, 'm599');
    expect(frames.first.text, 'm100'); // oldest 100 trimmed
  });

  test(
    'RealtimeTabsClosed does not clobber frames appended during teardown',
    () async {
      final fake2 = _FakeConnection()..closeGate = Completer<void>();
      when(() => service.connectWebSocket('wss://y')).thenReturn(fake2);
      await connect(); // t1 on `fake`
      bloc.add(
        const Connect(tabId: 't2', kind: RequestKind.webSocket, url: 'wss://y'),
      );
      await bloc.stream.firstWhere((s) => s.sessionFor('t2').connected);

      // t2's teardown suspends inside fake2.close() …
      bloc.add(const RealtimeTabsClosed({'t2'}));
      await Future<void>.delayed(Duration.zero);
      // … while t1 keeps streaming and its frames land in state …
      fake.controller.add(RealtimeFrame.incoming('during-teardown'));
      await bloc.stream.firstWhere(
        (s) =>
            s.sessionFor('t1').frames.any((f) => f.text == 'during-teardown'),
      );

      // … then the teardown resumes and folds the closed tab out.
      fake2.closeGate!.complete();
      await bloc.stream.firstWhere((s) => !s.sessions.containsKey('t2'));

      expect(
        bloc.state.sessionFor('t1').frames.map((f) => f.text),
        contains('during-teardown'),
        reason:
            'the TabsClosed fold must derive from live state, not a '
            'pre-teardown snapshot that clobbers frames appended meanwhile',
      );
    },
  );

  test(
    'a frame arriving during close() cannot flush into the closed bloc',
    () async {
      final fake2 = _FakeConnection();
      when(() => service.connectWebSocket('wss://y')).thenReturn(fake2);
      await connect(); // t1 on `fake`
      bloc.add(
        const Connect(tabId: 't2', kind: RequestKind.webSocket, url: 'wss://y'),
      );
      await bloc.stream.firstWhere((s) => s.sessionFor('t2').connected);

      // Queue a frame for t2 (broadcast delivery is a microtask) and start
      // close() in the same turn: close() clears the flush timers, suspends
      // awaiting t1's subscription cancel, and the queued frame then lands
      // in _bufferFrame — which (without the isClosed guards) arms a fresh
      // 16ms flush timer that add()s into the closed bloc.
      fake2.controller.add(RealtimeFrame.incoming('during-close'));
      await bloc.close();

      // Let the re-armed timer fire: without the guards it throws StateError
      // ('Cannot add new events after calling close') as an uncaught error.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.isClosed, isTrue);
    },
  );

  test(
    'Disconnect flushes frames still in the coalescing buffer into the log',
    () async {
      await connect();
      fake.controller.add(RealtimeFrame.incoming('last-words'));
      await Future<void>.delayed(
        Duration.zero,
      ); // buffered; 16ms flush timer armed
      bloc.add(const Disconnect('t1'));
      await bloc.stream.firstWhere((s) => !s.sessionFor('t1').connected);

      expect(
        bloc.state.sessionFor('t1').frames.map((f) => f.text),
        contains('last-words'),
        reason:
            'the last ≤16ms of traffic before the user hit DISCONNECT must '
            'be flushed into the log, not discarded with the coalescing '
            'buffer',
      );
      // …and once the coalesce window elapses, nothing (e.g. a stale batch)
      // may flip the session back to connected — the composer would be
      // re-enabled with no live connection behind it.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.sessionFor('t1').connected, isFalse);
    },
  );

  test(
    'a second Connect during the first teardown wins — the slower first '
    'connect must bail, not overwrite the live connection',
    () async {
      await connect(); // t1 on `fake`
      // Connect #1 suspends tearing down `fake` (in production this is a
      // real network wait: closing a dead socket can take seconds).
      fake.closeGate = Completer<void>();
      final fakeC = _FakeConnection();
      when(() => service.connectWebSocket('wss://c')).thenReturn(fakeC);
      bloc.add(
        const Connect(tabId: 't1', kind: RequestKind.webSocket, url: 'wss://b'),
      );
      await Future<void>.delayed(Duration.zero); // suspended in teardown
      // Connect #2 for the SAME tab finds nothing left to close, completes
      // first, and stores fakeC as t1's live connection. (No firstWhere:
      // the fresh session is value-equal to the old connected one, so
      // Equatable suppresses the emission.)
      bloc.add(
        const Connect(tabId: 't1', kind: RequestKind.webSocket, url: 'wss://c'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.sessionFor('t1').connected, isTrue);
      // Connect #1 resumes with a stale epoch: it must bail without creating
      // a connection for 'wss://b' — pre-fix it stored one over fakeC,
      // leaking fakeC's socket + subscription into the same log forever.
      fake.closeGate!.complete();
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => service.connectWebSocket('wss://b'));
      expect(fakeC.closed, isFalse);
      bloc.add(const SendRealtimeMessage('t1', 'ping'));
      await Future<void>.delayed(Duration.zero);
      expect(
        fakeC.sent,
        ['ping'],
        reason: "sends must route to the second connect's live connection",
      );
    },
  );

  test(
    'a Connect superseded by RealtimeTabsClosed during teardown creates '
    'neither a connection nor a ghost session',
    () async {
      await connect(); // t1 on `fake`
      fake.closeGate = Completer<void>();
      bloc.add(
        const Connect(tabId: 't1', kind: RequestKind.webSocket, url: 'wss://b'),
      );
      await Future<void>.delayed(Duration.zero); // suspended in teardown
      bloc.add(const RealtimeTabsClosed({'t1'}));
      await bloc.stream.firstWhere((s) => !s.sessions.containsKey('t1'));
      fake.closeGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      verifyNever(() => service.connectWebSocket('wss://b'));
      expect(
        bloc.state.sessions.containsKey('t1'),
        isFalse,
        reason:
            'the in-flight connect resuming after the tab closed must not '
            'resurrect a session (its socket would stream into dead state '
            'until app exit)',
      );
    },
  );

  test(
    'a synchronous connect throw surfaces as an error frame, not an '
    'unhandled zone error',
    () async {
      // With any enabled header (the desktop path), IOWebSocketChannel
      // .connect throws SYNCHRONOUSLY for a non-ws scheme — dart:io's
      // WebSocket.connect validates outside its async body. Pre-fix the
      // throw escaped _onConnect and CONNECT visibly did nothing.
      when(
        () => service.connectWebSocket(any()),
      ).thenThrow(const FormatException('bad scheme'));
      bloc.add(
        const Connect(
          tabId: 'tx',
          kind: RequestKind.webSocket,
          url: '{{base}}/ws',
        ),
      );
      await bloc.stream.firstWhere(
        (s) => s.sessionFor('tx').frames.isNotEmpty,
      );

      final session = bloc.state.sessionFor('tx');
      expect(session.connected, isFalse);
      expect(session.frames.single.direction, RealtimeDirection.error);
      expect(session.frames.single.text, contains('bad scheme'));
    },
  );

  test('normalizes http/https to ws/wss for WebSocket connects', () async {
    // Postman behavior: an http(s) URL pasted into a WS request connects via
    // the matching ws(s) scheme instead of throwing synchronously.
    bloc.add(
      const Connect(
        tabId: 't1',
        kind: RequestKind.webSocket,
        url: 'http://example.com/ws',
      ),
    );
    await bloc.stream.firstWhere((s) => s.sessionFor('t1').connected);
    verify(() => service.connectWebSocket('ws://example.com/ws')).called(1);

    bloc.add(
      const Connect(
        tabId: 't1',
        kind: RequestKind.webSocket,
        url: ' HTTPS://Example.com/ws ',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    verify(() => service.connectWebSocket('wss://Example.com/ws')).called(1);
  });

  test(
    'SSE URLs are passed through unnormalized (http IS the transport)',
    () async {
      final sse = _FakeConnection();
      when(() => service.connectSse(any())).thenReturn(sse);
      bloc.add(
        const Connect(
          tabId: 't2',
          kind: RequestKind.sse,
          url: 'https://example.com/events',
        ),
      );
      await bloc.stream.firstWhere((s) => s.sessionFor('t2').connected);
      verify(() => service.connectSse('https://example.com/events')).called(1);
    },
  );

  test(
    'frames buffered under the old connection never leak into a '
    'reconnected session',
    () async {
      await connect(); // t1 on `fake`
      final fakeC = _FakeConnection();
      when(() => service.connectWebSocket('wss://c')).thenReturn(fakeC);
      fake.controller.add(RealtimeFrame.incoming('stale'));
      await Future<void>.delayed(
        Duration.zero,
      ); // buffered; 16ms flush timer armed
      bloc.add(
        const Connect(tabId: 't1', kind: RequestKind.webSocket, url: 'wss://c'),
      );
      // Past the coalesce window: a batch from the old generation carries a
      // stale epoch and must be dropped, not appended to the fresh log. (No
      // firstWhere: the fresh session is value-equal to the old connected
      // one, so Equatable suppresses the reconnect emission.)
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.sessionFor('t1').frames, isEmpty);
      expect(bloc.state.sessionFor('t1').connected, isTrue);
    },
  );
}

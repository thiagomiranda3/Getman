// Equality/props tests for every RealtimeBloc event: equal instances compare
// equal, and each constructor field participates in Equatable props.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';

void main() {
  group('Connect', () {
    const base = Connect(
      tabId: 't1',
      kind: RequestKind.webSocket,
      url: 'ws://host/socket',
      headers: {'Authorization': 'Bearer x'},
    );

    test('equal instances compare equal', () {
      const same = Connect(
        tabId: 't1',
        kind: RequestKind.webSocket,
        url: 'ws://host/socket',
        headers: {'Authorization': 'Bearer x'},
      );
      expect(base, equals(same));
      expect(base.hashCode, same.hashCode);
    });

    test('headers default to an empty map', () {
      const noHeaders = Connect(
        tabId: 't1',
        kind: RequestKind.sse,
        url: 'http://host/events',
      );
      expect(noHeaders.headers, isEmpty);
    });

    test('every field participates in equality', () {
      expect(
        base,
        isNot(
          const Connect(
            tabId: 'OTHER',
            kind: RequestKind.webSocket,
            url: 'ws://host/socket',
            headers: {'Authorization': 'Bearer x'},
          ),
        ),
      );
      expect(
        base,
        isNot(
          const Connect(
            tabId: 't1',
            kind: RequestKind.sse,
            url: 'ws://host/socket',
            headers: {'Authorization': 'Bearer x'},
          ),
        ),
      );
      expect(
        base,
        isNot(
          const Connect(
            tabId: 't1',
            kind: RequestKind.webSocket,
            url: 'ws://other/socket',
            headers: {'Authorization': 'Bearer x'},
          ),
        ),
      );
      expect(
        base,
        isNot(
          const Connect(
            tabId: 't1',
            kind: RequestKind.webSocket,
            url: 'ws://host/socket',
          ),
        ),
      );
    });

    test('props expose tabId, kind, url, headers', () {
      expect(base.props, [
        't1',
        RequestKind.webSocket,
        'ws://host/socket',
        const {'Authorization': 'Bearer x'},
      ]);
    });
  });

  group('SendRealtimeMessage', () {
    test('equal instances compare equal', () {
      expect(
        const SendRealtimeMessage('t1', 'hello'),
        equals(const SendRealtimeMessage('t1', 'hello')),
      );
    });

    test('differs by tabId and by text', () {
      expect(
        const SendRealtimeMessage('t1', 'hello'),
        isNot(const SendRealtimeMessage('t2', 'hello')),
      );
      expect(
        const SendRealtimeMessage('t1', 'hello'),
        isNot(const SendRealtimeMessage('t1', 'bye')),
      );
    });

    test('props expose tabId and text', () {
      expect(const SendRealtimeMessage('t1', 'hello').props, ['t1', 'hello']);
    });
  });

  group('Disconnect', () {
    test('equal instances compare equal, differs by tabId', () {
      expect(const Disconnect('t1'), equals(const Disconnect('t1')));
      expect(const Disconnect('t1'), isNot(const Disconnect('t2')));
    });

    test('props expose tabId', () {
      expect(const Disconnect('t1').props, ['t1']);
    });
  });

  group('FrameReceived', () {
    const frame = RealtimeFrame(
      direction: RealtimeDirection.incoming,
      text: 'hi',
      timestampMs: 100,
    );

    test('equal instances compare equal', () {
      expect(
        const FrameReceived('t1', frame),
        equals(const FrameReceived('t1', frame)),
      );
    });

    test('differs by tabId and by frame', () {
      expect(
        const FrameReceived('t1', frame),
        isNot(const FrameReceived('t2', frame)),
      );
      expect(
        const FrameReceived('t1', frame),
        isNot(
          const FrameReceived(
            't1',
            RealtimeFrame(
              direction: RealtimeDirection.error,
              text: 'boom',
              timestampMs: 100,
            ),
          ),
        ),
      );
    });

    test('props expose tabId and frame', () {
      expect(const FrameReceived('t1', frame).props, ['t1', frame]);
    });
  });
}

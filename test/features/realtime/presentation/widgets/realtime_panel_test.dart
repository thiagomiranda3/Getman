import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/realtime/presentation/widgets/realtime_panel.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends Mock implements TabsBloc {}

class MockRealtimeBloc extends Mock implements RealtimeBloc {}

class _FakeRealtimeEvent extends Fake implements RealtimeEvent {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeRealtimeEvent()));

  late MockTabsBloc tabsBloc;
  late MockRealtimeBloc realtimeBloc;

  void stubRealtime(RealtimeState state) {
    when(() => realtimeBloc.state).thenReturn(state);
    when(
      () => realtimeBloc.stream,
    ).thenAnswer((_) => const Stream<RealtimeState>.empty());
  }

  setUp(() {
    tabsBloc = MockTabsBloc();
    realtimeBloc = MockRealtimeBloc();
    when(() => tabsBloc.state).thenReturn(
      const TabsState(
        tabs: [
          HttpRequestTabEntity(
            tabId: 't1',
            config: HttpRequestConfigEntity(
              id: 't1',
              kind: RequestKind.webSocket,
            ),
          ),
        ],
      ),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: RepositoryProvider<TabsBloc>.value(
            value: tabsBloc,
            child: BlocProvider<RealtimeBloc>.value(
              value: realtimeBloc,
              child: const RealtimePanel(tabId: 't1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows connected status, frames, and a composer for WebSocket', (
    tester,
  ) async {
    stubRealtime(
      RealtimeState(
        sessions: {
          't1': RealtimeSession(
            connected: true,
            frames: [RealtimeFrame.incoming('hello world')],
          ),
        },
      ),
    );

    await pump(tester);

    expect(find.text('CONNECTED'), findsOneWidget);
    expect(find.text('hello world'), findsOneWidget);
    // Brutalist logView uses ▼ glyph for incoming (not 'IN').
    expect(find.text('▼'), findsOneWidget);
    // WebSocket gets a message composer.
    expect(find.widgetWithText(ElevatedButton, 'SEND'), findsOneWidget);
  });

  testWidgets('disconnected with no frames shows the empty prompt', (
    tester,
  ) async {
    stubRealtime(const RealtimeState());

    await pump(tester);

    expect(find.text('DISCONNECTED'), findsOneWidget);
    expect(find.text('CONNECT TO START MESSAGING'), findsOneWidget);
  });

  testWidgets('SSE shows the stream prompt and no composer', (tester) async {
    when(() => tabsBloc.state).thenReturn(
      const TabsState(
        tabs: [
          HttpRequestTabEntity(
            tabId: 't1',
            config: HttpRequestConfigEntity(id: 't1', kind: RequestKind.sse),
          ),
        ],
      ),
    );
    stubRealtime(const RealtimeState());

    await pump(tester);

    expect(find.text('CONNECT TO STREAM EVENTS'), findsOneWidget);
    // SSE is receive-only: no message input, no SEND button.
    expect(
      find.byKey(const ValueKey('realtime_message_input')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('realtime_send_button')), findsNothing);
  });

  testWidgets('disconnected WebSocket composer is disabled', (tester) async {
    stubRealtime(const RealtimeState());

    await pump(tester);

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('realtime_message_input')),
    );
    expect(input.enabled, isFalse);
    final send = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('realtime_send_button')),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets('SEND dispatches SendRealtimeMessage and clears the composer', (
    tester,
  ) async {
    stubRealtime(
      const RealtimeState(sessions: {'t1': RealtimeSession(connected: true)}),
    );

    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('realtime_message_input')),
      'hello',
    );
    await tester.tap(find.byKey(const ValueKey('realtime_send_button')));
    await tester.pump();

    verify(
      () => realtimeBloc.add(const SendRealtimeMessage('t1', 'hello')),
    ).called(1);
    // The composer is cleared after sending.
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('submitting the composer via keyboard sends the message', (
    tester,
  ) async {
    stubRealtime(
      const RealtimeState(sessions: {'t1': RealtimeSession(connected: true)}),
    );

    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('realtime_message_input')),
      'ping',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    verify(
      () => realtimeBloc.add(const SendRealtimeMessage('t1', 'ping')),
    ).called(1);
  });

  testWidgets('SEND with an empty composer dispatches nothing', (
    tester,
  ) async {
    stubRealtime(
      const RealtimeState(sessions: {'t1': RealtimeSession(connected: true)}),
    );

    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('realtime_send_button')));
    await tester.pump();

    verifyNever(() => realtimeBloc.add(any()));
  });

  testWidgets('renders open, outgoing, close, and error frames', (
    tester,
  ) async {
    stubRealtime(
      const RealtimeState(
        sessions: {
          't1': RealtimeSession(
            connected: true,
            frames: [
              RealtimeFrame(
                direction: RealtimeDirection.open,
                text: 'Connected',
                timestampMs: 1,
              ),
              RealtimeFrame(
                direction: RealtimeDirection.outgoing,
                text: 'ping',
                timestampMs: 2,
              ),
              RealtimeFrame(
                direction: RealtimeDirection.error,
                text: 'boom',
                timestampMs: 3,
              ),
              RealtimeFrame(
                direction: RealtimeDirection.close,
                text: 'Disconnected',
                timestampMs: 4,
              ),
            ],
          ),
        },
      ),
    );

    await pump(tester);

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('ping'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
  });

  testWidgets('log rebuilds as frames stream in (length + tail timestamp)', (
    tester,
  ) async {
    const f1 = RealtimeFrame(
      direction: RealtimeDirection.incoming,
      text: 'first',
      timestampMs: 1,
    );
    const f2 = RealtimeFrame(
      direction: RealtimeDirection.incoming,
      text: 'second',
      timestampMs: 2,
    );
    const f3 = RealtimeFrame(
      direction: RealtimeDirection.incoming,
      text: 'third',
      timestampMs: 3,
    );
    when(() => realtimeBloc.state).thenReturn(
      const RealtimeState(
        sessions: {
          't1': RealtimeSession(connected: true, frames: [f1]),
        },
      ),
    );
    // First emission grows the log (length change); the second replaces the
    // tail at the same length (timestamp change) — both must rebuild.
    when(() => realtimeBloc.stream).thenAnswer(
      (_) => Stream.fromIterable(const [
        RealtimeState(
          sessions: {
            't1': RealtimeSession(connected: true, frames: [f1, f2]),
          },
        ),
        RealtimeState(
          sessions: {
            't1': RealtimeSession(connected: true, frames: [f1, f3]),
          },
        ),
      ]),
    );

    await pump(tester);

    expect(find.text('first'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
    expect(find.text('second'), findsNothing);
  });
}

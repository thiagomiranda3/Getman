import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/realtime/presentation/widgets/realtime_panel.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends Mock implements TabsBloc {}

class MockRealtimeBloc extends Mock implements RealtimeBloc {}

void main() {
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
    expect(find.text('IN'), findsOneWidget);
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
}

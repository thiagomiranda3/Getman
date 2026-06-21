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

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockRealtimeBloc extends Mock implements RealtimeBloc {}

void main() {
  late _MockTabsBloc tabsBloc;
  late _MockRealtimeBloc realtimeBloc;

  void stubRealtime(RealtimeState state) {
    when(() => realtimeBloc.state).thenReturn(state);
    when(
      () => realtimeBloc.stream,
    ).thenAnswer((_) => const Stream<RealtimeState>.empty());
  }

  setUp(() {
    tabsBloc = _MockTabsBloc();
    realtimeBloc = _MockRealtimeBloc();
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

  testWidgets('logView slot: direction glyphs + frame text appear', (
    tester,
  ) async {
    stubRealtime(
      RealtimeState(
        sessions: {
          't1': RealtimeSession(
            connected: true,
            frames: [
              RealtimeFrame.incoming('server says hello'),
              RealtimeFrame.outgoing('client ping'),
            ],
          ),
        },
      ),
    );

    await pump(tester);

    // Brutalist logView uses glyph markers (▼ / ▲) rather than 'IN' / 'OUT'.
    expect(find.text('▼'), findsOneWidget);
    expect(find.text('▲'), findsOneWidget);
    expect(find.text('server says hello'), findsOneWidget);
    expect(find.text('client ping'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('statusBanner slot: CONNECTED appears for connected state', (
    tester,
  ) async {
    stubRealtime(
      RealtimeState(
        sessions: {
          't1': RealtimeSession(
            connected: true,
            frames: [RealtimeFrame.incoming('hi')],
          ),
        },
      ),
    );

    await pump(tester);

    expect(find.text('CONNECTED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('statusBanner slot: DISCONNECTED appears when not connected', (
    tester,
  ) async {
    stubRealtime(const RealtimeState());

    await pump(tester);

    expect(find.text('DISCONNECTED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logView uses a scrollable ListView (not NeverScrollable)', (
    tester,
  ) async {
    stubRealtime(
      RealtimeState(
        sessions: {
          't1': RealtimeSession(
            connected: true,
            frames: [RealtimeFrame.incoming('msg')],
          ),
        },
      ),
    );

    await pump(tester);

    // The ListView in logView must NOT use NeverScrollableScrollPhysics.
    final listViews = tester.widgetList<ListView>(find.byType(ListView));
    final hasNeverScrollable = listViews.any(
      (lv) => lv.physics is NeverScrollableScrollPhysics,
    );
    expect(hasNeverScrollable, isFalse);
    expect(tester.takeException(), isNull);
  });
}

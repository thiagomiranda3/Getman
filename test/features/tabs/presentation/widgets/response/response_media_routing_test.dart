import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// Lightweight fake blocs that only expose `state` — the widget reads state via
// context.read<...>() / BlocBuilder and never dispatches events here.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);
}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc(super.initialState);
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc(super.initialState);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(super.initialState);
}

void main() {
  const tabId = 'tab-routing';

  HttpRequestTabEntity tabWith({HttpResponseEntity? response}) {
    return HttpRequestTabEntity(
      tabId: tabId,
      config: const HttpRequestConfigEntity(
        id: 'cfg-routing',
        url: 'https://api.example.com/photo.png',
      ),
      response: response,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required HttpRequestTabEntity tab,
  }) async {
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>(
            create: (_) => _FakeTabsBloc(TabsState(tabs: [tab])),
          ),
          BlocProvider<CollectionsBloc>(
            create: (_) => _FakeCollectionsBloc(CollectionsState()),
          ),
          BlocProvider<HistoryBloc>(
            create: (_) => _FakeHistoryBloc(const HistoryState()),
          ),
          BlocProvider<SettingsBloc>(
            create: (_) => _FakeSettingsBloc(
              const SettingsState(settings: SettingsEntity()),
            ),
          ),
        ],
        child: MaterialApp(
          theme: resolveTheme(kBrutalistThemeId)(
            Brightness.light,
            isCompact: false,
          ),
          home: Scaffold(
            body: ResponseBodyView(
              tabId: tabId,
              responseController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('image response routes to image preview', (tester) async {
    // 1x1 transparent PNG.
    final png = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    await pump(
      tester,
      tab: tabWith(
        response: HttpResponseEntity(
          statusCode: 200,
          body: '',
          headers: const {'content-type': 'image/png'},
          durationMs: 5,
          bodyBytes: png,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('media_preview_image')), findsOneWidget);
  });

  testWidgets('media with null bytes shows not-stored placeholder', (
    tester,
  ) async {
    // content-type video/mp4 but bodyBytes == null (restored tab).
    await pump(
      tester,
      tab: tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '',
          headers: {'content-type': 'video/mp4'},
          durationMs: 5,
          // bodyBytes deliberately omitted (null) — simulates a restored tab.
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('media_preview_placeholder')),
      findsOneWidget,
    );
  });
}

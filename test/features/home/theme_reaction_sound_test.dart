import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/features/home/presentation/widgets/theme_reaction_listener.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:provider/provider.dart';

class _FakeTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _FakeTabsBloc() : super(const TabsState());
  void push(TabsState s) => emit(s);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _FakeSettingsBloc(SettingsEntity s) : super(SettingsState(settings: s));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RecordingSound implements ThemeSoundService {
  final calls = <String>[];
  @override
  Future<void> play(String themeId, ThemeReaction r) async =>
      calls.add('$themeId:${r.kind.name}');
  @override
  void dispose() {}
}

void main() {
  testWidgets('plays sound only when enabled', (tester) async {
    final tabs = _FakeTabsBloc();
    final controller = ThemeReactionController();
    final pulse = WorkspacePulseController();
    final sound = _RecordingSound();

    Future<void> pumpWith({required bool enabled}) async {
      final settings = _FakeSettingsBloc(
        SettingsEntity(enableThemeSounds: enabled, themeId: 'rpg'),
      );
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: MultiRepositoryProvider(
            providers: [
              ChangeNotifierProvider<ThemeReactionController>.value(
                value: controller,
              ),
              ChangeNotifierProvider<WorkspacePulseController>.value(
                value: pulse,
              ),
              RepositoryProvider<ThemeSoundService>.value(value: sound),
            ],
            child: const MaterialApp(
              home: ThemeReactionListener(child: SizedBox()),
            ),
          ),
        ),
      );
    }

    await pumpWith(enabled: false);
    tabs.push(
      const TabsState(
        reactionSeq: 1,
        lastReaction: ThemeReaction(
          kind: ThemeReactionKind.success,
          statusCode: 200,
        ),
      ),
    );
    await tester.pump();
    expect(sound.calls, isEmpty);

    await pumpWith(enabled: true);
    tabs.push(
      const TabsState(
        reactionSeq: 2,
        lastReaction: ThemeReaction(
          kind: ThemeReactionKind.success,
          statusCode: 200,
        ),
      ),
    );
    await tester.pump();
    expect(sound.calls, ['rpg:success']);

    await tabs.close();
    controller.dispose();
    pulse.dispose();
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Bridges request-driven [TabsState] reactions into the app-wide
/// [ThemeReactionController], at the widget layer (it holds both), so TabsBloc
/// never depends on a UI controller — the same rule ChainingWriteBackListener
/// follows. Fires exactly once per `reactionSeq` increase.
///
/// Also plays a themed sound effect when `enableThemeSounds` is on in
/// [SettingsBloc]. [ThemeSoundService.play] is fire-and-forget — it never
/// throws.
class ThemeReactionListener extends StatelessWidget {
  const ThemeReactionListener({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) =>
          next.reactionSeq != prev.reactionSeq && next.lastReaction != null,
      listener: (context, state) {
        final reaction = state.lastReaction!;
        context.read<ThemeReactionController>().fire(reaction);
        context.read<WorkspacePulseController>().bump();
        final settings = context.read<SettingsBloc>().state.settings;
        if (settings.enableThemeSounds) {
          // play() never throws (service contract); fire-and-forget.
          // ignore: discarded_futures
          context.read<ThemeSoundService>().play(settings.themeId, reaction);
        }
      },
      child: child,
    );
  }
}

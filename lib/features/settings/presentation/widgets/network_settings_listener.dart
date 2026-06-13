import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Pushes network-related settings into the live [NetworkService] whenever they
/// change. Keeps [SettingsBloc] free of any dependency on the network service
/// (the coordinating widget holds both, per the project's bloc-coupling rule).
/// `listenWhen` is gated to the six network fields so unrelated settings
/// keystrokes never touch Dio.
class NetworkSettingsListener extends StatelessWidget {
  final Widget child;
  const NetworkSettingsListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (prev, next) {
        final a = prev.settings;
        final b = next.settings;
        return a.connectTimeoutMs != b.connectTimeoutMs ||
            a.sendTimeoutMs != b.sendTimeoutMs ||
            a.receiveTimeoutMs != b.receiveTimeoutMs ||
            a.followRedirects != b.followRedirects ||
            a.verifySsl != b.verifySsl ||
            a.proxyUrl != b.proxyUrl;
      },
      listener: (context, state) =>
          context.read<NetworkService>().applyConfig(state.settings.toNetworkConfig()),
      child: child,
    );
  }
}

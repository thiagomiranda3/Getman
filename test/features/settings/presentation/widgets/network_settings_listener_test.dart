import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/widgets/network_settings_listener.dart';
import 'package:mocktail/mocktail.dart';

class MockNetworkService extends Mock implements NetworkService {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

void main() {
  setUpAll(() {
    registerFallbackValue(NetworkConfig.defaults);
    registerFallbackValue(const SettingsEntity());
  });

  late MockNetworkService network;
  late SettingsBloc bloc;

  setUp(() {
    network = MockNetworkService();
    final save = MockSaveSettingsUseCase();
    when(() => save.call(any())).thenAnswer((_) async {});
    bloc = SettingsBloc(
      saveSettingsUseCase: save,
      initialSettings: const SettingsEntity(),
    );
  });

  tearDown(() => bloc.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      RepositoryProvider<NetworkService>.value(
        value: network,
        child: BlocProvider.value(
          value: bloc,
          child: const NetworkSettingsListener(child: SizedBox()),
        ),
      ),
    );
  }

  testWidgets('applies config when a network field changes', (tester) async {
    await pump(tester);

    // runAsync drives the real event loop so the bloc's broadcast state stream
    // reaches the BlocListener (the FakeAsync zone alone won't deliver it).
    await tester.runAsync(() async {
      bloc.add(const UpdateConnectTimeout(1234));
      await bloc.stream.firstWhere((s) => s.settings.connectTimeoutMs == 1234);
    });
    await tester.pump();

    verify(() => network.applyConfig(any())).called(1);
  });

  testWidgets('applies config when maxRedirects changes', (tester) async {
    await pump(tester);

    await tester.runAsync(() async {
      bloc.add(const UpdateMaxRedirects(2));
      await bloc.stream.firstWhere((s) => s.settings.maxRedirects == 2);
    });
    await tester.pump();

    verify(() => network.applyConfig(any())).called(1);
  });

  testWidgets('applies config when the client certificate changes', (
    tester,
  ) async {
    await pump(tester);

    await tester.runAsync(() async {
      bloc.add(
        const UpdateClientCertificate(certPath: '/c.pem', keyPath: '/k.pem'),
      );
      await bloc.stream.firstWhere(
        (s) => s.settings.clientCertPath == '/c.pem',
      );
    });
    await tester.pump();

    verify(() => network.applyConfig(any())).called(1);
  });

  testWidgets('ignores non-network setting changes', (tester) async {
    await pump(tester);

    await tester.runAsync(() async {
      bloc.add(const UpdateDarkMode(isDarkMode: true));
      await bloc.stream.firstWhere((s) => s.settings.isDarkMode);
    });
    await tester.pump();

    verifyNever(() => network.applyConfig(any()));
  });
}

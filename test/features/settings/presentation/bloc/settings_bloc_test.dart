import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:mocktail/mocktail.dart';

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

void main() {
  late MockSaveSettingsUseCase save;
  late SettingsBloc bloc;

  setUpAll(() => registerFallbackValue(const SettingsEntity()));

  setUp(() {
    save = MockSaveSettingsUseCase();
    when(() => save.call(any())).thenAnswer((_) async {});
    bloc = SettingsBloc(saveSettingsUseCase: save, initialSettings: const SettingsEntity());
  });

  tearDown(() => bloc.close());

  test('UpdateConnectTimeout updates state and persists', () async {
    bloc.add(const UpdateConnectTimeout(1234));
    await bloc.stream.firstWhere((s) => s.settings.connectTimeoutMs == 1234);
    expect(bloc.state.settings.connectTimeoutMs, 1234);
    verify(() => save.call(any())).called(1);
  });

  test('timeouts clamp negatives to zero', () async {
    bloc.add(const UpdateReceiveTimeout(-9));
    await bloc.stream.firstWhere((s) => s.settings.receiveTimeoutMs == 0);
    expect(bloc.state.settings.receiveTimeoutMs, 0);
  });

  test('UpdateVerifySsl and UpdateFollowRedirects toggle their flags', () async {
    bloc.add(const UpdateVerifySsl(false));
    await bloc.stream.firstWhere((s) => s.settings.verifySsl == false);
    bloc.add(const UpdateFollowRedirects(false));
    await bloc.stream.firstWhere((s) => s.settings.followRedirects == false);
    expect(bloc.state.settings.verifySsl, isFalse);
    expect(bloc.state.settings.followRedirects, isFalse);
  });

  test('UpdateMaxRedirects updates and persists; clamps below 1 to 1', () async {
    bloc.add(const UpdateMaxRedirects(3));
    await bloc.stream.firstWhere((s) => s.settings.maxRedirects == 3);
    expect(bloc.state.settings.maxRedirects, 3);
    verify(() => save.call(any())).called(1);

    // 0 with followRedirects on makes dart:io throw on the first redirect, so
    // it is clamped up to 1 — disabling redirects is FOLLOW REDIRECTS off.
    bloc.add(const UpdateMaxRedirects(0));
    await bloc.stream.firstWhere((s) => s.settings.maxRedirects == 1);
    expect(bloc.state.settings.maxRedirects, 1);
  });

  test('UpdateClientCertificate sets the trio, then clears it', () async {
    bloc.add(const UpdateClientCertificate(
      certPath: '/c.pem',
      keyPath: '/k.pem',
      passphrase: 'secret',
    ));
    await bloc.stream.firstWhere((s) => s.settings.clientCertPath == '/c.pem');
    expect(bloc.state.settings.clientKeyPath, '/k.pem');
    expect(bloc.state.settings.clientCertPassphrase, 'secret');

    bloc.add(const UpdateClientCertificate());
    await bloc.stream.firstWhere((s) => s.settings.clientCertPath == null);
    expect(bloc.state.settings.clientKeyPath, isNull);
    expect(bloc.state.settings.clientCertPassphrase, isNull);
  });

  test('UpdateProxyUrl sets and clears the proxy', () async {
    bloc.add(const UpdateProxyUrl('127.0.0.1:8888'));
    await bloc.stream.firstWhere((s) => s.settings.proxyUrl == '127.0.0.1:8888');
    bloc.add(const UpdateProxyUrl(null));
    await bloc.stream.firstWhere((s) => s.settings.proxyUrl == null);
    expect(bloc.state.settings.proxyUrl, isNull);
  });

  test('UpdateWorkspacePath connects with a bookmark, then disconnect clears both', () async {
    bloc.add(const UpdateWorkspacePath('/ws', bookmark: 'Ym0='));
    await bloc.stream.firstWhere((s) => s.settings.workspacePath == '/ws');
    expect(bloc.state.settings.workspaceBookmark, 'Ym0=');

    // Disconnect (no bookmark arg) must clear the bookmark too, not strand it.
    bloc.add(const UpdateWorkspacePath(null));
    await bloc.stream.firstWhere((s) => s.settings.workspacePath == null);
    expect(bloc.state.settings.workspaceBookmark, isNull);
  });
}

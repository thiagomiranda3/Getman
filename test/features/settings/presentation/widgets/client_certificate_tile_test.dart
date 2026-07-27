// Widget tests for ClientCertificateTile:
// - renders "not set" placeholders and hides CLEAR when no cert/key is set;
// - shows just the file names (both / and \ separators) once set, with CLEAR;
// - typing a passphrase dispatches UpdateClientCertificate preserving the
//   cert/key pair (trimmed; blank clears to null);
// - CHOOSE CERT / CHOOSE KEY drive the file picker (mocked at the
//   method-channel level) and update only their own path;
// - a cancelled pick dispatches nothing;
// - CLEAR wipes the whole trio and empties the passphrase field.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/widgets/client_certificate_tile.dart';
import 'package:mocktail/mocktail.dart';

class _MockSaveSettings extends Mock implements SaveSettingsUseCase {}

/// file_picker's default platform implementation talks over this channel;
/// mocking it lets the tile's real `FilePicker.pickFiles` call run end-to-end
/// without any implementation imports.
const _pickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

/// Installs a picker mock that answers every pick with [path] (or a
/// cancellation when [path] is null).
void _mockPicker(WidgetTester tester, {String? path}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _pickerChannel,
    (call) async {
      if (path == null) return null; // user cancelled the dialog
      return <Map<dynamic, dynamic>>[
        {
          'name': path.split(RegExp(r'[/\\]')).last,
          'path': path,
          'size': 0,
        },
      ];
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _pickerChannel,
      null,
    ),
  );
}

SettingsBloc _bloc({SettingsEntity? initial}) {
  final save = _MockSaveSettings();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: initial ?? const SettingsEntity(),
  );
}

Future<void> _pump(WidgetTester tester, SettingsBloc bloc) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(
          body: SingleChildScrollView(child: ClientCertificateTile()),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const SettingsEntity());
  });

  testWidgets('renders placeholders and no CLEAR when nothing is set', (
    tester,
  ) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    expect(find.text('CLIENT CERTIFICATE (mTLS)'), findsOneWidget);
    expect(find.text('Cert: not set'), findsOneWidget);
    expect(find.text('Key: not set'), findsOneWidget);
    expect(find.text('CHOOSE CERT'), findsOneWidget);
    expect(find.text('CHOOSE KEY'), findsOneWidget);
    expect(find.text('CLEAR'), findsNothing);
  });

  testWidgets(
    'shows file names for configured paths (both separator styles) plus CLEAR',
    (tester) async {
      final bloc = _bloc(
        initial: const SettingsEntity(
          clientCertPath: '/certs/nested/client-cert.pem',
          clientKeyPath: r'C:\keys\client-key.pem',
        ),
      );
      addTearDown(bloc.close);
      await _pump(tester, bloc);

      expect(find.text('Cert: client-cert.pem'), findsOneWidget);
      expect(find.text('Key: client-key.pem'), findsOneWidget);
      expect(find.text('CLEAR'), findsOneWidget);
    },
  );

  testWidgets('prefills the passphrase field from settings', (tester) async {
    final bloc = _bloc(
      initial: const SettingsEntity(clientCertPassphrase: 'hunter2'),
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hunter2');
    expect(field.obscureText, isTrue);
  });

  testWidgets(
    'typing a passphrase dispatches the full trio with cert/key preserved',
    (tester) async {
      final bloc = _bloc(
        initial: const SettingsEntity(
          clientCertPath: '/c.pem',
          clientKeyPath: '/k.pem',
        ),
      );
      addTearDown(bloc.close);
      await _pump(tester, bloc);

      await tester.enterText(find.byType(TextField), '  secret  ');
      await tester.pump();

      expect(bloc.state.settings.clientCertPassphrase, 'secret');
      expect(bloc.state.settings.clientCertPath, '/c.pem');
      expect(bloc.state.settings.clientKeyPath, '/k.pem');
    },
  );

  testWidgets('blanking the passphrase clears it to null', (tester) async {
    final bloc = _bloc(
      initial: const SettingsEntity(
        clientCertPath: '/c.pem',
        clientCertPassphrase: 'old',
      ),
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(bloc.state.settings.clientCertPassphrase, isNull);
    expect(bloc.state.settings.clientCertPath, '/c.pem');
  });

  testWidgets('CHOOSE CERT picks a file and updates only the cert path', (
    tester,
  ) async {
    final bloc = _bloc(
      initial: const SettingsEntity(
        clientKeyPath: '/existing/key.pem',
        clientCertPassphrase: 'pw',
      ),
    );
    addTearDown(bloc.close);
    _mockPicker(tester, path: '/picked/new-cert.pem');
    await _pump(tester, bloc);

    await tester.tap(find.text('CHOOSE CERT'));
    await tester.pumpAndSettle();

    expect(bloc.state.settings.clientCertPath, '/picked/new-cert.pem');
    expect(bloc.state.settings.clientKeyPath, '/existing/key.pem');
    expect(bloc.state.settings.clientCertPassphrase, 'pw');
    expect(find.text('Cert: new-cert.pem'), findsOneWidget);
  });

  testWidgets('CHOOSE KEY picks a file and updates only the key path', (
    tester,
  ) async {
    final bloc = _bloc(
      initial: const SettingsEntity(clientCertPath: '/existing/cert.pem'),
    );
    addTearDown(bloc.close);
    _mockPicker(tester, path: '/picked/new-key.pem');
    await _pump(tester, bloc);

    await tester.tap(find.text('CHOOSE KEY'));
    await tester.pumpAndSettle();

    expect(bloc.state.settings.clientKeyPath, '/picked/new-key.pem');
    expect(bloc.state.settings.clientCertPath, '/existing/cert.pem');
    expect(find.text('Key: new-key.pem'), findsOneWidget);
  });

  testWidgets('a cancelled pick dispatches nothing', (tester) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    _mockPicker(tester); // handler returns null → cancel
    await _pump(tester, bloc);

    await tester.tap(find.text('CHOOSE CERT'));
    await tester.pumpAndSettle();

    expect(bloc.state.settings.clientCertPath, isNull);
    expect(find.text('Cert: not set'), findsOneWidget);
  });

  testWidgets('CLEAR wipes the trio and empties the passphrase field', (
    tester,
  ) async {
    final bloc = _bloc(
      initial: const SettingsEntity(
        clientCertPath: '/c.pem',
        clientKeyPath: '/k.pem',
        clientCertPassphrase: 'pw',
      ),
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.tap(find.text('CLEAR'));
    await tester.pumpAndSettle();

    expect(bloc.state.settings.clientCertPath, isNull);
    expect(bloc.state.settings.clientKeyPath, isNull);
    expect(bloc.state.settings.clientCertPassphrase, isNull);
    expect(find.text('Cert: not set'), findsOneWidget);
    expect(find.text('Key: not set'), findsOneWidget);
    expect(find.text('CLEAR'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });
}

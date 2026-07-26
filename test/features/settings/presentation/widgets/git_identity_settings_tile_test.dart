// Widget tests for GitIdentitySettingsTile:
// - renders the COMMIT IDENTITY header with name/email fields prefilled from
//   the current settings;
// - editing one field dispatches UpdateGitIdentity carrying the OTHER field's
//   current value (the sentinel keeps untouched fields intact);
// - blanking a field clears it to null (an explicit clear, not "unchanged");
// - values are trimmed before dispatch.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/widgets/git_identity_settings_tile.dart';
import 'package:mocktail/mocktail.dart';

class _MockSaveSettings extends Mock implements SaveSettingsUseCase {}

const ValueKey<String> _nameField = ValueKey('git_identity_name_field');
const ValueKey<String> _emailField = ValueKey('git_identity_email_field');

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
          body: SingleChildScrollView(child: GitIdentitySettingsTile()),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const SettingsEntity());
  });

  testWidgets('renders header and prefills both fields from settings', (
    tester,
  ) async {
    final bloc = _bloc(
      initial: const SettingsEntity(
        gitUserName: 'Ada Lovelace',
        gitUserEmail: 'ada@example.com',
      ),
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    expect(find.text('COMMIT IDENTITY'), findsOneWidget);
    final name = tester.widget<TextField>(find.byKey(_nameField));
    final email = tester.widget<TextField>(find.byKey(_emailField));
    expect(name.controller!.text, 'Ada Lovelace');
    expect(email.controller!.text, 'ada@example.com');
  });

  testWidgets('empty identity renders empty fields', (tester) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    final name = tester.widget<TextField>(find.byKey(_nameField));
    final email = tester.widget<TextField>(find.byKey(_emailField));
    expect(name.controller!.text, isEmpty);
    expect(email.controller!.text, isEmpty);
  });

  testWidgets('typing a name keeps the stored email intact', (tester) async {
    final bloc = _bloc(
      initial: const SettingsEntity(gitUserEmail: 'keep@example.com'),
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.enterText(find.byKey(_nameField), '  Grace Hopper  ');
    await tester.pump();

    expect(bloc.state.settings.gitUserName, 'Grace Hopper');
    expect(bloc.state.settings.gitUserEmail, 'keep@example.com');
  });

  testWidgets('typing an email keeps the stored name intact', (tester) async {
    final bloc = _bloc(initial: const SettingsEntity(gitUserName: 'Keep Me'));
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.enterText(find.byKey(_emailField), 'new@example.com');
    await tester.pump();

    expect(bloc.state.settings.gitUserEmail, 'new@example.com');
    expect(bloc.state.settings.gitUserName, 'Keep Me');
  });

  testWidgets('blanking the name clears it to null, email untouched', (
    tester,
  ) async {
    final bloc = _bloc(
      initial: const SettingsEntity(
        gitUserName: 'Old Name',
        gitUserEmail: 'keep@example.com',
      ),
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.enterText(find.byKey(_nameField), '   ');
    await tester.pump();

    expect(bloc.state.settings.gitUserName, isNull);
    expect(bloc.state.settings.gitUserEmail, 'keep@example.com');
  });

  testWidgets('blanking the email clears it to null, name untouched', (
    tester,
  ) async {
    final bloc = _bloc(
      initial: const SettingsEntity(
        gitUserName: 'Keep Me',
        gitUserEmail: 'old@example.com',
      ),
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.enterText(find.byKey(_emailField), '');
    await tester.pump();

    expect(bloc.state.settings.gitUserEmail, isNull);
    expect(bloc.state.settings.gitUserName, 'Keep Me');
  });
}

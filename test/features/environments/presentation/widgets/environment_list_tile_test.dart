// Widget tests for EnvironmentListTile: renders the env name, highlights when
// selected, shows the active-environment marker, and invokes callbacks on tap,
// export, and delete.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/auris/auris_theme.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/widgets/environment_list_tile.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

SettingsBloc _makeSettingsBloc({String? activeEnvId}) {
  final uc = MockSaveSettingsUseCase();
  when(() => uc(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: uc,
    initialSettings: SettingsEntity(activeEnvironmentId: activeEnvId),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required EnvironmentEntity environment,
  required bool isSelected,
  required VoidCallback onTap,
  required VoidCallback onDelete,
  required VoidCallback onExport,
  String? activeEnvId,
  ThemeData? theme,
}) async {
  final settingsBloc = _makeSettingsBloc(activeEnvId: activeEnvId);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? brutalistTheme(Brightness.light),
      home: Scaffold(
        body: BlocProvider.value(
          value: settingsBloc,
          child: EnvironmentListTile(
            environment: environment,
            isSelected: isSelected,
            onTap: onTap,
            onDelete: onDelete,
            onExport: onExport,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const SettingsEntity());
  });

  final env = EnvironmentEntity(id: 'e1', name: 'Production');

  testWidgets('renders the environment name', (tester) async {
    await _pump(
      tester,
      environment: env,
      isSelected: false,
      onTap: () {},
      onDelete: () {},
      onExport: () {},
    );

    expect(find.text('Production'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap callback is invoked on tap', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      environment: env,
      isSelected: false,
      onTap: () => tapped = true,
      onDelete: () {},
      onExport: () {},
    );

    // Tap on the env name text (within the InkWell) to avoid ambiguity with the
    // icon button InkWells.
    await tester.tap(find.text('Production'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete button invokes onDelete callback', (tester) async {
    var deleted = false;
    await _pump(
      tester,
      environment: env,
      isSelected: false,
      onTap: () {},
      onDelete: () => deleted = true,
      onExport: () {},
    );

    await tester.tap(find.byTooltip('Delete environment'));
    await tester.pump();

    expect(deleted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export button invokes onExport callback', (tester) async {
    var exported = false;
    await _pump(
      tester,
      environment: env,
      isSelected: false,
      onTap: () {},
      onDelete: () {},
      onExport: () => exported = true,
    );

    await tester.tap(find.byTooltip('Export environment'));
    await tester.pump();

    expect(exported, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows check_circle icon when env is the active environment', (
    tester,
  ) async {
    await _pump(
      tester,
      environment: env,
      isSelected: false,
      onTap: () {},
      onDelete: () {},
      onExport: () {},
      activeEnvId: 'e1',
    );

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected highlight uses colorScheme.primary, not the near-black '
    'primaryColor under AURIS dark',
    (tester) async {
      // Regression: theme.primaryColor is near-black under AURIS/Glass dark —
      // a known project trap. The highlight must key off colorScheme.primary,
      // matching quick_env_switcher.dart's selection highlight.
      final theme = aurisTheme(Brightness.dark);
      await _pump(
        tester,
        environment: env,
        isSelected: true,
        onTap: () {},
        onDelete: () {},
        onExport: () {},
        theme: theme,
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(EnvironmentListTile),
          matching: find.byType(Container),
        ),
      );
      expect(
        container.color,
        theme.colorScheme.primary.withValues(alpha: 0.3),
      );
      expect(
        container.color,
        isNot(theme.primaryColor.withValues(alpha: 0.3)),
      );
    },
  );

  testWidgets('does not show check_circle when env is not active', (
    tester,
  ) async {
    await _pump(
      tester,
      environment: env,
      isSelected: false,
      onTap: () {},
      onDelete: () {},
      onExport: () {},
      activeEnvId: 'other',
    );

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

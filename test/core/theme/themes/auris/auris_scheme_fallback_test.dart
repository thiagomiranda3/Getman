// Regression for the AURIS-only exception flood.
//
// Root cause: AppComponents.lerp AND AppDecoration.lerp both return `this`, so
// during any theme cross-fade the AURIS component + decoration closures survive
// into a transitional ThemeData — but AurisScheme is dropped (the other theme
// lacks it). Every `Auris*` widget / decoration force-unwraps
// `Theme.of(context).extension<AurisScheme>()!` → throws on every frame →
// RenderErrorBox storm + RawTooltip ticker flood.
//
// Fix: the auris slots/decorations fall back to plain/default rendering when
// AurisScheme is absent. These tests reproduce the scheme-less state by taking
// the real AURIS theme and removing AurisScheme, then asserting nothing throws.

import 'package:auris/auris.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/themes/auris/auris_theme.dart';
import 'package:google_fonts/google_fonts.dart';

/// The real AURIS theme with [AurisScheme] stripped — exactly the transitional
/// state (auris components + decorations active, scheme gone).
ThemeData _aurisWithoutScheme() {
  final auris = aurisTheme(Brightness.dark);
  final exts = auris.extensions.values.where((e) => e is! AurisScheme).toList();
  return auris.copyWith(extensions: exts);
}

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget Function(BuildContext) build,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: Builder(builder: build),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('precondition: stripped theme really has no AurisScheme', () {
    expect(_aurisWithoutScheme().extension<AurisScheme>(), isNull);
  });

  testWidgets('all auris component slots render without throwing when '
      'AurisScheme is absent', (tester) async {
    final theme = _aurisWithoutScheme();
    await _pump(
      tester,
      theme,
      (context) {
        final c = context.appComponents;
        return ListView(
          children: [
            c.methodBadge(context, method: 'GET'),
            c.statusBadge(context, statusCode: 200),
            c.metric(context, label: 'TIME', value: '42', unit: 'ms'),
            c.toggle(context, value: true, onChanged: (_) {}),
            c.dataRow(
              context,
              label: 'content-type',
              value: 'application/json',
            ),
            c.statusBanner(
              context,
              state: AppBannerState.success,
              message: 'OK',
            ),
            SizedBox(
              height: 60,
              child: c.surface(context, child: const Text('S')),
            ),
            SizedBox(
              height: 60,
              child: c.logView(
                context,
                lines: const [
                  AppLogLine(text: 'ping', kind: AppLogLineKind.outgoing),
                ],
              ),
            ),
            SizedBox(height: 60, child: c.pendingIndicator(context)),
            c.select(
              context,
              AppSelectSpec(
                items: const [AppSelectItem(label: 'ONE')],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ],
        );
      },
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auris decorations render without throwing when AurisScheme is '
      'absent', (tester) async {
    final theme = _aurisWithoutScheme();
    await _pump(
      tester,
      theme,
      (context) {
        final d = context.appDecoration;
        return d.scaffoldBackground(
          context,
          child: Column(
            children: [
              DecoratedBox(
                decoration: d.panelBox(context),
                child: const SizedBox(width: 80, height: 30),
              ),
              DecoratedBox(
                decoration: d.tabShape(
                  context,
                  active: true,
                  hovered: false,
                  isFirst: true,
                ),
                child: const SizedBox(width: 80, height: 30),
              ),
            ],
          ),
        );
      },
    );
    expect(tester.takeException(), isNull);
  });
}

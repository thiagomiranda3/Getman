import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  testWidgets('every default slot renders without throwing', (tester) async {
    final components = defaultAppComponents();
    final theme = resolveThemeData(null, Brightness.light, isCompact: false)
        .copyWith(
          extensions: [
            ...resolveThemeData(
              null,
              Brightness.light,
              isCompact: false,
            ).extensions.values,
            components,
          ],
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            final c = context.appComponents;
            return Scaffold(
              body: ListView(
                children: [
                  c.surface(context, child: const Text('panel')),
                  c.methodBadge(context, method: 'GET'),
                  c.statusBadge(context, statusCode: 200),
                  c.metric(context, label: 'TIME', value: '142', unit: 'ms'),
                  c.toggle(context, value: true, onChanged: (_) {}, label: 'X'),
                  SizedBox(
                    height: 120,
                    child: c.logView(
                      context,
                      lines: const [
                        AppLogLine(text: 'hi', kind: AppLogLineKind.open),
                      ],
                    ),
                  ),
                  c.dataRow(
                    context,
                    label: 'Content-Type',
                    value: 'application/json',
                  ),
                  c.select(
                    context,
                    AppSelectSpec(
                      items: const [AppSelectItem(label: 'GET')],
                      selectedIndex: 0,
                      onSelected: (_) {},
                    ),
                  ),
                  c.pendingIndicator(context),
                  c.statusBanner(
                    context,
                    state: AppBannerState.success,
                    message: 'CONNECTED',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

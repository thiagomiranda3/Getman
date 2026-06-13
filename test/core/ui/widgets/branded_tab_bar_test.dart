import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(body: child),
    ));
  }

  testWidgets('renders all labels inside a DefaultTabController', (tester) async {
    await pump(
      tester,
      const DefaultTabController(
        length: 3,
        child: BrandedTabBar(labels: ['PARAMS', 'HEADERS', 'BODY']),
      ),
    );

    expect(find.text('PARAMS'), findsOneWidget);
    expect(find.text('HEADERS'), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('uses an explicit controller when given one', (tester) async {
    final controller = TabController(length: 2, vsync: tester);
    addTearDown(controller.dispose);

    await pump(
      tester,
      BrandedTabBar(labels: const ['A', 'B'], controller: controller),
    );
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(controller.index, 1);
  });

  testWidgets('styles the indicator from the theme, not hardcoded colors', (tester) async {
    await pump(
      tester,
      const DefaultTabController(
        length: 2,
        child: BrandedTabBar(labels: ['A', 'B']),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final theme = brutalistTheme(Brightness.light);
    expect((tabBar.indicator as BoxDecoration?)?.color, theme.primaryColor);
    expect(tabBar.labelColor, theme.colorScheme.onPrimary);
  });
}

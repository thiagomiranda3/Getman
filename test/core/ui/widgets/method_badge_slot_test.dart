import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('renders method text via methodBadge slot', (tester) async {
    await pump(tester, const MethodBadge(method: 'GET'));

    expect(find.text('GET'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders small variant without exception', (tester) async {
    await pump(tester, const MethodBadge(method: 'POST', small: true));

    expect(find.text('POST'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders all common HTTP methods', (tester) async {
    for (final method in ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']) {
      await pump(tester, MethodBadge(method: method));
      expect(find.text(method), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

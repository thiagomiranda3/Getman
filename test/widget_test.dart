import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_methods.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_palette.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';

Widget _wrap(Widget child, {bool dark = false, bool compact = false}) {
  return MaterialApp(
    theme: resolveTheme(kBrutalistThemeId)(
      dark ? Brightness.dark : Brightness.light,
      isCompact: compact,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('MethodBadge renders every supported HTTP method without crashing', (tester) async {
    for (final method in HttpMethods.all) {
      await tester.pumpWidget(_wrap(MethodBadge(method: method)));
      expect(find.text(method), findsOneWidget);
    }
  });

  testWidgets('MethodBadge uses the palette-driven method color', (tester) async {
    await tester.pumpWidget(_wrap(const MethodBadge(method: 'GET')));
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('GET'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, BrutalistPalette.methodColors['GET']);
  });

  testWidgets('MethodBadge renders in both compact and normal layouts', (tester) async {
    await tester.pumpWidget(_wrap(const MethodBadge(method: 'POST'), compact: true));
    expect(find.text('POST'), findsOneWidget);

    await tester.pumpWidget(_wrap(const MethodBadge(method: 'POST')));
    expect(find.text('POST'), findsOneWidget);
  });

  testWidgets('MethodBadge renders in dark theme', (tester) async {
    await tester.pumpWidget(_wrap(const MethodBadge(method: 'DELETE'), dark: true));
    expect(find.text('DELETE'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_text_field.dart';
import 'package:getman/core/utils/layered_variable_context.dart';

Widget _host(Widget child) => MaterialApp(
  theme: resolveTheme('brutalist')(Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  const ctx = LayeredVariableContext(
    environmentVariables: {'host': 'example.com', 'token': 'abc'},
    environmentName: 'Staging',
  );

  testWidgets('typing {{ opens the suggestion overlay', (tester) async {
    final controller = VariableHighlightController();
    final focus = FocusNode();
    await tester.pumpWidget(
      _host(
        VariableTextField(
          variables: ctx,
          controller: controller,
          focusNode: focus,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();

    expect(find.text('host'), findsOneWidget);
    expect(find.text('token'), findsOneWidget);
  });

  testWidgets('accepting a suggestion inserts {{name}}', (tester) async {
    final controller = VariableHighlightController();
    final focus = FocusNode();
    await tester.pumpWidget(
      _host(
        VariableTextField(
          variables: ctx,
          controller: controller,
          focusNode: focus,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '{{ho');
    await tester.pumpAndSettle();
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();

    expect(controller.text, '{{host}}');
  });

  testWidgets('style parameter is forwarded to the inner TextField', (
    tester,
  ) async {
    const testStyle = TextStyle(fontSize: 21, fontWeight: FontWeight.w900);
    final controller = VariableHighlightController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      _host(
        VariableTextField(
          variables: ctx,
          controller: controller,
          focusNode: focus,
          onChanged: (_) {},
          style: testStyle,
        ),
      ),
    );

    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.style?.fontSize, 21);
    expect(tf.style?.fontWeight, FontWeight.w900);
  });

  testWidgets('empty context renders a plain field with no overlay', (
    tester,
  ) async {
    final controller = VariableHighlightController();
    final focus = FocusNode();
    await tester.pumpWidget(
      _host(
        VariableTextField(
          variables: LayeredVariableContext.empty,
          controller: controller,
          focusNode: focus,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    // No suggestions to show.
    expect(find.byType(ListView), findsNothing);
  });
}

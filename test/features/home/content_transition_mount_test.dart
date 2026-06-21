import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

void main() {
  testWidgets('contentTransition hook receives the composite key', (
    tester,
  ) async {
    final seenKeys = <String>[];
    final motion = const AppMotion().copyWith(
      contentTransition: (context, {required child, required transitionKey}) {
        seenKeys.add(transitionKey);
        return child;
      },
    );
    Widget build(String key) => MaterialApp(
      home: Builder(
        builder: (context) => motion.contentTransition(
          context,
          transitionKey: key,
          child: const Text('c'),
        ),
      ),
    );
    await tester.pumpWidget(build('p1/t1'));
    await tester.pumpWidget(build('p1/t2'));
    expect(seenKeys, contains('p1/t1'));
    expect(seenKeys, contains('p1/t2'));
    expect(find.text('c'), findsOneWidget);
  });
}

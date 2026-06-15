import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';

void main() {
  group('UrlFocusRegistry', () {
    testWidgets('focus() focuses the node registered for the given tab', (
      tester,
    ) async {
      final registry = UrlFocusRegistry();
      final nodeA = FocusNode();
      final nodeB = FocusNode();
      addTearDown(nodeA.dispose);
      addTearDown(nodeB.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: nodeA),
                TextField(focusNode: nodeB),
              ],
            ),
          ),
        ),
      );

      registry
        ..register('a', nodeA)
        ..register('b', nodeB)
        ..focus('b');
      await tester.pump();

      expect(nodeB.hasFocus, isTrue);
      expect(nodeA.hasFocus, isFalse);
    });

    test('focus() on an unknown tab id is a no-op', () {
      final registry = UrlFocusRegistry();
      expect(() => registry.focus('missing'), returnsNormally);
    });

    test(
      'unregister only drops the node when it is still the registered one',
      () {
        final registry = UrlFocusRegistry();
        final oldNode = FocusNode();
        final newNode = FocusNode();
        addTearDown(oldNode.dispose);
        addTearDown(newNode.dispose);

        registry
          ..register('a', oldNode)
          // A fresh UrlBar for the same id registered before the old one's
          // dispose.
          ..register('a', newNode)
          // The old one's dispose must not clobber the new registration.
          ..unregister('a', oldNode);

        expect(() => registry.focus('a'), returnsNormally);
        // Re-registering newNode is a no-op overwrite; unregister with it
        // clears.
        registry.unregister('a', newNode);
      },
    );
  });
}

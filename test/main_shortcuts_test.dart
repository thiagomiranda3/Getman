import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/main.dart';

void main() {
  // SingleActivator has no value equality (Shortcuts indexes by trigger +
  // accepts, not map-key ==), so scan the entries by trigger/modifiers rather
  // than looking up with a freshly-constructed activator.
  JumpToTabIntent? jumpFor(
    LogicalKeyboardKey key, {
    bool meta = false,
    bool control = false,
  }) {
    for (final entry in appShortcuts.entries) {
      final a = entry.key;
      if (a is SingleActivator &&
          a.trigger == key &&
          a.meta == meta &&
          a.control == control &&
          entry.value is JumpToTabIntent) {
        return entry.value as JumpToTabIntent;
      }
    }
    return null;
  }

  group('appShortcuts', () {
    test('Ctrl+Tab / Ctrl+Shift+Tab map to next / previous tab', () {
      expect(
        appShortcuts[const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
        )],
        isA<NextTabIntent>(),
      );
      expect(
        appShortcuts[const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        )],
        isA<PrevTabIntent>(),
      );
    });

    test('Cmd/Ctrl+1..9 map to JumpToTabIntent with a 0-based index', () {
      expect(jumpFor(LogicalKeyboardKey.digit1, meta: true)?.index, 0);
      expect(jumpFor(LogicalKeyboardKey.digit1, control: true)?.index, 0);
      expect(jumpFor(LogicalKeyboardKey.digit9, meta: true)?.index, 8);
      expect(jumpFor(LogicalKeyboardKey.digit9, control: true)?.index, 8);
    });

    test('existing bindings still resolve', () {
      expect(
        appShortcuts[const SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: true,
        )],
        isA<NewTabIntent>(),
      );
    });

    test('Cmd/Ctrl+E map to SwitchEnvironmentIntent', () {
      expect(
        appShortcuts[const SingleActivator(
          LogicalKeyboardKey.keyE,
          meta: true,
        )],
        isA<SwitchEnvironmentIntent>(),
      );
      expect(
        appShortcuts[const SingleActivator(
          LogicalKeyboardKey.keyE,
          control: true,
        )],
        isA<SwitchEnvironmentIntent>(),
      );
    });
  });
}

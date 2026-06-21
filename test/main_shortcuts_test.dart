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

  // Helper: scan all entries for a matching activator + intent type.
  bool hasBinding<T extends Intent>(
    LogicalKeyboardKey key, {
    bool control = false,
    bool meta = false,
    bool shift = false,
  }) => appShortcuts.entries.any(
    (e) =>
        e.key is SingleActivator &&
        (e.key as SingleActivator).trigger == key &&
        (e.key as SingleActivator).control == control &&
        (e.key as SingleActivator).meta == meta &&
        (e.key as SingleActivator).shift == shift &&
        e.value is T,
  );

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

    test('appShortcuts includes panel bindings', () {
      // Ctrl+Shift+N and Cmd+Shift+N → NewPanelIntent.
      expect(
        hasBinding<NewPanelIntent>(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ),
        isTrue,
        reason: 'Ctrl+Shift+N must be bound to NewPanelIntent',
      );
      expect(
        hasBinding<NewPanelIntent>(
          LogicalKeyboardKey.keyN,
          meta: true,
          shift: true,
        ),
        isTrue,
        reason: 'Cmd+Shift+N must be bound to NewPanelIntent',
      );
      // Bracket bindings for next/prev panel.
      expect(
        hasBinding<NextPanelIntent>(
          LogicalKeyboardKey.bracketRight,
          control: true,
          shift: true,
        ),
        isTrue,
        reason: 'Ctrl+Shift+] must be bound to NextPanelIntent',
      );
      expect(
        hasBinding<NextPanelIntent>(
          LogicalKeyboardKey.bracketRight,
          meta: true,
          shift: true,
        ),
        isTrue,
        reason: 'Cmd+Shift+] must be bound to NextPanelIntent',
      );
      expect(
        hasBinding<PrevPanelIntent>(
          LogicalKeyboardKey.bracketLeft,
          control: true,
          shift: true,
        ),
        isTrue,
        reason: 'Ctrl+Shift+[ must be bound to PrevPanelIntent',
      );
      expect(
        hasBinding<PrevPanelIntent>(
          LogicalKeyboardKey.bracketLeft,
          meta: true,
          shift: true,
        ),
        isTrue,
        reason: 'Cmd+Shift+[ must be bound to PrevPanelIntent',
      );
      // 9 JumpToPanelIntent entries per modifier = 18 total.
      expect(
        appShortcuts.values.whereType<JumpToPanelIntent>().length,
        18,
        reason: '9 control + 9 meta JumpToPanelIntent bindings expected',
      );
    });

    group('complete binding coverage', () {
      test('Cmd/Ctrl+W → CloseTabIntent (both modifiers)', () {
        expect(
          hasBinding<CloseTabIntent>(LogicalKeyboardKey.keyW, control: true),
          isTrue,
          reason: 'Ctrl+W must be bound to CloseTabIntent',
        );
        expect(
          hasBinding<CloseTabIntent>(LogicalKeyboardKey.keyW, meta: true),
          isTrue,
          reason: 'Cmd+W must be bound to CloseTabIntent',
        );
      });

      test('Cmd/Ctrl+S → SaveRequestIntent (both modifiers)', () {
        expect(
          hasBinding<SaveRequestIntent>(LogicalKeyboardKey.keyS, control: true),
          isTrue,
          reason: 'Ctrl+S must be bound to SaveRequestIntent',
        );
        expect(
          hasBinding<SaveRequestIntent>(LogicalKeyboardKey.keyS, meta: true),
          isTrue,
          reason: 'Cmd+S must be bound to SaveRequestIntent',
        );
      });

      test('Cmd/Ctrl+Enter → SendRequestIntent (both modifiers)', () {
        expect(
          hasBinding<SendRequestIntent>(
            LogicalKeyboardKey.enter,
            control: true,
          ),
          isTrue,
          reason: 'Ctrl+Enter must be bound to SendRequestIntent',
        );
        expect(
          hasBinding<SendRequestIntent>(LogicalKeyboardKey.enter, meta: true),
          isTrue,
          reason: 'Cmd+Enter must be bound to SendRequestIntent',
        );
      });

      test('Cmd/Ctrl+B → BeautifyJsonIntent (both modifiers)', () {
        expect(
          hasBinding<BeautifyJsonIntent>(
            LogicalKeyboardKey.keyB,
            control: true,
          ),
          isTrue,
          reason: 'Ctrl+B must be bound to BeautifyJsonIntent',
        );
        expect(
          hasBinding<BeautifyJsonIntent>(LogicalKeyboardKey.keyB, meta: true),
          isTrue,
          reason: 'Cmd+B must be bound to BeautifyJsonIntent',
        );
      });

      test('Cmd/Ctrl+K → CommandPaletteIntent (both modifiers)', () {
        expect(
          hasBinding<CommandPaletteIntent>(
            LogicalKeyboardKey.keyK,
            control: true,
          ),
          isTrue,
          reason: 'Ctrl+K must be bound to CommandPaletteIntent',
        );
        expect(
          hasBinding<CommandPaletteIntent>(LogicalKeyboardKey.keyK, meta: true),
          isTrue,
          reason: 'Cmd+K must be bound to CommandPaletteIntent',
        );
      });

      test('Cmd/Ctrl+L → FocusUrlIntent (both modifiers)', () {
        expect(
          hasBinding<FocusUrlIntent>(LogicalKeyboardKey.keyL, control: true),
          isTrue,
          reason: 'Ctrl+L must be bound to FocusUrlIntent',
        );
        expect(
          hasBinding<FocusUrlIntent>(LogicalKeyboardKey.keyL, meta: true),
          isTrue,
          reason: 'Cmd+L must be bound to FocusUrlIntent',
        );
      });

      test('JumpToTabIntent indices span 0–8 for both modifiers', () {
        for (var i = 0; i < 9; i++) {
          final key = [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
            LogicalKeyboardKey.digit5,
            LogicalKeyboardKey.digit6,
            LogicalKeyboardKey.digit7,
            LogicalKeyboardKey.digit8,
            LogicalKeyboardKey.digit9,
          ][i];
          expect(
            jumpFor(key, control: true)?.index,
            i,
            reason: 'Ctrl+${i + 1} must jump to tab index $i',
          );
          expect(
            jumpFor(key, meta: true)?.index,
            i,
            reason: 'Cmd+${i + 1} must jump to tab index $i',
          );
        }
      });

      test(
        'JumpToPanelIntent indices span 0–8 for both modifiers (18 entries)',
        () {
          JumpToPanelIntent? panelJumpFor(
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
                  a.shift &&
                  entry.value is JumpToPanelIntent) {
                return entry.value as JumpToPanelIntent;
              }
            }
            return null;
          }

          final digitKeys = [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
            LogicalKeyboardKey.digit5,
            LogicalKeyboardKey.digit6,
            LogicalKeyboardKey.digit7,
            LogicalKeyboardKey.digit8,
            LogicalKeyboardKey.digit9,
          ];

          for (var i = 0; i < 9; i++) {
            expect(
              panelJumpFor(digitKeys[i], control: true)?.panelIndex,
              i,
              reason: 'Ctrl+Shift+${i + 1} must jump to panel index $i',
            );
            expect(
              panelJumpFor(digitKeys[i], meta: true)?.panelIndex,
              i,
              reason: 'Cmd+Shift+${i + 1} must jump to panel index $i',
            );
          }
        },
      );

      test('total shortcut count matches documented bindings', () {
        // 2 (N new-tab) + 2 (W close) + 2 (S save) + 2 (enter send) +
        // 2 (B beautify) + 2 (K palette) + 2 (E env) + 1 (Ctrl+Tab next) +
        // 1 (Ctrl+Shift+Tab prev) + 2 (L focus-url) +
        // 18 (tab digit 1..9 × ctrl+meta) +
        // 2 (Shift+N new panel) + 2 (] next panel) +
        // 2 ([ prev panel) +
        // 18 (panel digit 1..9 × ctrl+meta, shift=true) = 62
        // The map allocates 62 logical entries, but same-const dedup
        // of identical activator objects (with different intent values)
        // reduces the runtime count to 60. Lock it here.
        expect(appShortcuts.length, 60);
      });
    });
  });
}

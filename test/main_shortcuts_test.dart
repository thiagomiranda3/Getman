import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/main.dart';

void main() {
  // SingleActivator has no value equality (Shortcuts indexes by trigger +
  // accepts, not map-key ==), so scan the entries by trigger/modifiers rather
  // than looking up with a freshly-constructed activator.
  bool hasBinding<T extends Intent>(
    Map<ShortcutActivator, Intent> map,
    LogicalKeyboardKey key, {
    bool control = false,
    bool meta = false,
    bool shift = false,
  }) => map.entries.any(
    (e) =>
        e.key is SingleActivator &&
        (e.key as SingleActivator).trigger == key &&
        (e.key as SingleActivator).control == control &&
        (e.key as SingleActivator).meta == meta &&
        (e.key as SingleActivator).shift == shift &&
        e.value is T,
  );

  int? jumpIndexFor(
    Map<ShortcutActivator, Intent> map,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool control = false,
    bool shift = false,
  }) {
    for (final entry in map.entries) {
      final a = entry.key;
      if (a is SingleActivator &&
          a.trigger == key &&
          a.meta == meta &&
          a.control == control &&
          a.shift == shift) {
        final intent = entry.value;
        if (intent is JumpToTabIntent) return intent.index;
        if (intent is JumpToPanelIntent) return intent.panelIndex;
      }
    }
    return null;
  }

  const digitKeys = [
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

  // The primary-modifier shortcuts: (trigger, intent type, shift?). Each must
  // be bound to exactly the platform's primary modifier and NOT the other one.
  void runPrimaryModifierTests(Map<ShortcutActivator, Intent> map) {
    void single<T extends Intent>(
      LogicalKeyboardKey key, {
      bool shift = false,
    }) {
      expect(
        hasBinding<T>(map, key, meta: true, shift: shift),
        true,
        reason: '$T should bind ⌘${shift ? '+Shift' : ''}',
      );
      expect(
        hasBinding<T>(map, key, control: true, shift: shift),
        false,
        reason: '$T must NOT bind Ctrl on macOS',
      );
    }

    single<NewTabIntent>(LogicalKeyboardKey.keyN);
    single<CloseTabIntent>(LogicalKeyboardKey.keyW);
    single<SaveRequestIntent>(LogicalKeyboardKey.keyS);
    single<SendRequestIntent>(LogicalKeyboardKey.enter);
    single<BeautifyJsonIntent>(LogicalKeyboardKey.keyB);
    single<CommandPaletteIntent>(LogicalKeyboardKey.keyK);
    single<SwitchEnvironmentIntent>(LogicalKeyboardKey.keyE);
    single<FocusUrlIntent>(LogicalKeyboardKey.keyL);
    single<NewPanelIntent>(LogicalKeyboardKey.keyN, shift: true);
    single<NextPanelIntent>(LogicalKeyboardKey.bracketRight, shift: true);
    single<PrevPanelIntent>(LogicalKeyboardKey.bracketLeft, shift: true);
  }

  group('appShortcuts (macOS / useMeta: true)', () {
    final map = buildAppShortcuts(useMeta: true);

    test('all primary shortcuts use ⌘ only, never Ctrl', () {
      runPrimaryModifierTests(map);
    });

    test('Ctrl+S does NOT save on macOS (the reported bug)', () {
      expect(
        hasBinding<SaveRequestIntent>(map, LogicalKeyboardKey.keyS),
        false,
        reason: 'plain Ctrl+S must not be bound',
      );
      expect(
        hasBinding<SaveRequestIntent>(
          map,
          LogicalKeyboardKey.keyS,
          control: true,
        ),
        false,
        reason: 'Ctrl+S must not save on macOS',
      );
      expect(
        hasBinding<SaveRequestIntent>(map, LogicalKeyboardKey.keyS, meta: true),
        true,
        reason: '⌘+S must save on macOS',
      );
    });

    test('Ctrl+Tab / Ctrl+Shift+Tab stay cross-platform (Ctrl, not ⌘)', () {
      expect(
        hasBinding<NextTabIntent>(map, LogicalKeyboardKey.tab, control: true),
        true,
      );
      expect(
        hasBinding<PrevTabIntent>(
          map,
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ),
        true,
      );
      expect(
        hasBinding<NextTabIntent>(map, LogicalKeyboardKey.tab, meta: true),
        false,
        reason: '⌘+Tab is the macOS app switcher — must not be bound',
      );
    });

    test('⌘+1..9 jump to tab; ⌘+Shift+1..9 jump to panel', () {
      for (var i = 0; i < 9; i++) {
        expect(jumpIndexFor(map, digitKeys[i], meta: true), i);
        expect(jumpIndexFor(map, digitKeys[i], meta: true, shift: true), i);
        expect(
          jumpIndexFor(map, digitKeys[i], control: true),
          isNull,
          reason: 'Ctrl+${i + 1} must not jump on macOS',
        );
      }
    });
  });

  group('appShortcuts (Windows/Linux / useMeta: false)', () {
    final map = buildAppShortcuts(useMeta: false);

    test('all primary shortcuts use Ctrl only, never ⌘', () {
      void single<T extends Intent>(
        LogicalKeyboardKey key, {
        bool shift = false,
      }) {
        expect(hasBinding<T>(map, key, control: true, shift: shift), true);
        expect(
          hasBinding<T>(map, key, meta: true, shift: shift),
          false,
          reason: '$T must NOT bind ⌘ off macOS',
        );
      }

      single<NewTabIntent>(LogicalKeyboardKey.keyN);
      single<CloseTabIntent>(LogicalKeyboardKey.keyW);
      single<SaveRequestIntent>(LogicalKeyboardKey.keyS);
      single<SendRequestIntent>(LogicalKeyboardKey.enter);
      single<BeautifyJsonIntent>(LogicalKeyboardKey.keyB);
      single<CommandPaletteIntent>(LogicalKeyboardKey.keyK);
      single<SwitchEnvironmentIntent>(LogicalKeyboardKey.keyE);
      single<FocusUrlIntent>(LogicalKeyboardKey.keyL);
      single<NewPanelIntent>(LogicalKeyboardKey.keyN, shift: true);
      single<NextPanelIntent>(LogicalKeyboardKey.bracketRight, shift: true);
      single<PrevPanelIntent>(LogicalKeyboardKey.bracketLeft, shift: true);
    });

    test('Ctrl+S saves off macOS', () {
      expect(
        hasBinding<SaveRequestIntent>(
          map,
          LogicalKeyboardKey.keyS,
          control: true,
        ),
        true,
      );
    });

    test('Ctrl+1..9 jump to tab; Ctrl+Shift+1..9 jump to panel', () {
      for (var i = 0; i < 9; i++) {
        expect(jumpIndexFor(map, digitKeys[i], control: true), i);
        expect(jumpIndexFor(map, digitKeys[i], control: true, shift: true), i);
      }
    });
  });

  test('each platform map has exactly 31 single-modifier bindings', () {
    // 8 primary (N,W,S,Enter,B,K,E,L) + 2 tab-switch (Ctrl+Tab, Ctrl+Shift+Tab)
    // + 9 jump-to-tab + 3 panel (Shift+N, Shift+], Shift+[) + 9 jump-to-panel.
    expect(buildAppShortcuts(useMeta: true).length, 31);
    expect(buildAppShortcuts(useMeta: false).length, 31);
  });

  test('runtime appShortcuts is non-empty (built for the host platform)', () {
    expect(appShortcuts, isNotEmpty);
    expect(appShortcuts.length, 31);
  });
}

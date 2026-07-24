import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/navigation/shortcut_catalog.dart';

void main() {
  group('shortcutCatalog', () {
    test('lists every AppShortcutAction exactly once (both platforms)', () {
      for (final useMeta in [true, false]) {
        final actions = shortcutCatalog(
          useMeta: useMeta,
        ).map((e) => e.action).toList();
        expect(actions.toSet(), AppShortcutAction.values.toSet());
        expect(actions.length, AppShortcutAction.values.length);
      }
    });

    test('keeps every pre-catalog settings-tab entry verbatim', () {
      final titles = shortcutCatalog(
        useMeta: true,
      ).map((e) => e.title).toList();
      expect(
        titles,
        containsAll(<String>[
          'Send request',
          'Save request',
          'Beautify JSON',
          'Focus URL',
          'Command palette',
          'Switch environment',
          'New tab',
          'Close tab',
          'Next tab',
          'Previous tab',
          'Jump to tab 1–9',
          'New panel',
          'Next panel',
          'Previous panel',
          'Jump to panel 1–9',
        ]),
      );
    });

    test('groups into REQUEST/TABS/PANELS/HELP in display order', () {
      final sections = <String>[];
      for (final e in shortcutCatalog(useMeta: true)) {
        if (sections.isEmpty || sections.last != e.section) {
          sections.add(e.section);
        }
      }
      expect(sections, ['REQUEST', 'TABS', 'PANELS', 'HELP']);
    });

    test('next/previous tab stay Control-based even on macOS', () {
      final next = shortcutCatalog(
        useMeta: true,
      ).firstWhere((e) => e.action == AppShortcutAction.nextTab);
      expect(next.keyCaps, ['⌃', 'Tab']);
    });
  });

  group('shortcutHint', () {
    test('returns compact mac glyph forms when useMeta', () {
      expect(
        shortcutHint(AppShortcutAction.reopenClosedTab, useMeta: true),
        '⌘⇧T',
      );
      expect(shortcutHint(AppShortcutAction.send, useMeta: true), '⌘↩');
      expect(
        shortcutHint(AppShortcutAction.shortcutsHelp, useMeta: true),
        '⌘/',
      );
      expect(shortcutHint(AppShortcutAction.saveAll, useMeta: true), '⌘⌥S');
      expect(shortcutHint(AppShortcutAction.nextTab, useMeta: true), '⌃Tab');
    });

    test('returns Ctrl+ spelled forms otherwise', () {
      expect(
        shortcutHint(AppShortcutAction.reopenClosedTab, useMeta: false),
        'Ctrl+Shift+T',
      );
      expect(
        shortcutHint(AppShortcutAction.send, useMeta: false),
        'Ctrl+Enter',
      );
      expect(
        shortcutHint(AppShortcutAction.shortcutsHelp, useMeta: false),
        'Ctrl+/',
      );
      expect(
        shortcutHint(AppShortcutAction.saveAll, useMeta: false),
        'Ctrl+Alt+S',
      );
    });
  });
}

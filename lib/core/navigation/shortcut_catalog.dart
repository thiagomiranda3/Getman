// Single source of truth for keyboard-shortcut LABELS: every surface that
// displays a shortcut (settings SHORTCUTS tab, the ⌘/ cheat-sheet overlay,
// tooltip hints) reads shortcutCatalog()/shortcutHint() so they can never
// drift. The BINDINGS themselves live in main.dart's buildAppShortcuts —
// adding a shortcut means adding it in both places. Also home to
// useMetaShortcuts, the single macOS-vs-everything-else predicate every
// platform-aware surface reads.

import 'package:flutter/foundation.dart';

/// Whether shortcuts use ⌘ (meta) as the primary modifier — true only on
/// macOS (web on a Mac reports TargetPlatform.macOS too). THE single
/// platform predicate: buildAppShortcuts(useMeta:) in main.dart, every E2
/// tooltip hint, and the shortcut reference table/dialog all read this
/// getter — never re-derive from Theme.of(context).platform or
/// Platform.isMacOS.
bool get useMetaShortcuts => defaultTargetPlatform == TargetPlatform.macOS;

/// Every user-facing keyboard action Getman advertises. `reopenClosedTab`,
/// `saveAll`, and `shortcutsHelp` are cataloged ahead of their intents
/// landing (A2/A3/E1) so label surfaces ship in sync.
enum AppShortcutAction {
  newTab,
  closeTab,
  reopenClosedTab,
  save,
  saveAll,
  send,
  beautifyJson,
  commandPalette,
  envSwitcher,
  focusUrl,
  nextTab,
  prevTab,
  jumpToTab,
  newPanel,
  nextPanel,
  prevPanel,
  jumpToPanel,
  shortcutsHelp,
}

/// One catalog row. [keys] is the compact hint ('⌘⇧T' / 'Ctrl+Shift+T') for
/// tooltips; [keyCaps] is the same combo as individual key-cap tokens
/// (['⌘', '⇧', 'T']) for the settings tab / cheat-sheet rendering; [section]
/// is the display group heading ('REQUEST' / 'TABS' / 'PANELS' / 'HELP').
class ShortcutCatalogEntry {
  const ShortcutCatalogEntry({
    required this.action,
    required this.title,
    required this.description,
    required this.keys,
    required this.keyCaps,
    required this.section,
  });
  final AppShortcutAction action;
  final String title;
  final String description;
  final String keys;
  final List<String> keyCaps;
  final String section;
}

/// The full catalog in display order (sections contiguous). [useMeta] picks
/// macOS glyphs (⌘ ⇧ ⌥ ⌃, concatenated hints) vs spelled-out modifiers
/// (Ctrl/Shift/Alt, '+'-joined hints) — same platform split as
/// buildAppShortcuts(useMeta:). Next/Previous tab are Control-based on every
/// platform (⌘+Tab is the macOS app switcher), so they always render with
/// the Control modifier.
List<ShortcutCatalogEntry> shortcutCatalog({required bool useMeta}) {
  final mod = useMeta ? '⌘' : 'Ctrl';
  final shift = useMeta ? '⇧' : 'Shift';
  final alt = useMeta ? '⌥' : 'Alt';
  final ctrl = useMeta ? '⌃' : 'Ctrl';
  String hint(List<String> parts) => useMeta ? parts.join() : parts.join('+');

  return [
    // REQUEST
    ShortcutCatalogEntry(
      action: AppShortcutAction.send,
      title: 'Send request',
      description: "Send the active tab's request",
      keys: hint([mod, if (useMeta) '↩' else 'Enter']),
      keyCaps: [mod, 'Enter'],
      section: 'REQUEST',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.save,
      title: 'Save request',
      description: 'Save the request to its node',
      keys: hint([mod, 'S']),
      keyCaps: [mod, 'S'],
      section: 'REQUEST',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.saveAll,
      title: 'Save all',
      description: 'Save every dirty collection-linked tab',
      keys: hint([mod, alt, 'S']),
      keyCaps: [mod, alt, 'S'],
      section: 'REQUEST',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.beautifyJson,
      title: 'Beautify JSON',
      description: 'Format & indent the JSON body',
      keys: hint([mod, 'B']),
      keyCaps: [mod, 'B'],
      section: 'REQUEST',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.focusUrl,
      title: 'Focus URL',
      description: "Jump to the active tab's URL field",
      keys: hint([mod, 'L']),
      keyCaps: [mod, 'L'],
      section: 'REQUEST',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.commandPalette,
      title: 'Command palette',
      description: 'Fuzzy-jump to a request, environment, or theme',
      keys: hint([mod, 'K']),
      keyCaps: [mod, 'K'],
      section: 'REQUEST',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.envSwitcher,
      title: 'Switch environment',
      description: 'Open the quick environment switcher',
      keys: hint([mod, 'E']),
      keyCaps: [mod, 'E'],
      section: 'REQUEST',
    ),
    // TABS
    ShortcutCatalogEntry(
      action: AppShortcutAction.newTab,
      title: 'New tab',
      description: 'Open a new request tab',
      keys: hint([mod, 'N']),
      keyCaps: [mod, 'N'],
      section: 'TABS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.closeTab,
      title: 'Close tab',
      description: 'Close the active tab',
      keys: hint([mod, 'W']),
      keyCaps: [mod, 'W'],
      section: 'TABS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.reopenClosedTab,
      title: 'Reopen closed tab',
      description: 'Restore the most recently closed tab',
      keys: hint([mod, shift, 'T']),
      keyCaps: [mod, shift, 'T'],
      section: 'TABS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.nextTab,
      title: 'Next tab',
      description: 'Cycle to the next tab',
      keys: hint([ctrl, 'Tab']),
      keyCaps: [ctrl, 'Tab'],
      section: 'TABS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.prevTab,
      title: 'Previous tab',
      description: 'Cycle to the previous tab',
      keys: hint([ctrl, shift, 'Tab']),
      keyCaps: [ctrl, shift, 'Tab'],
      section: 'TABS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.jumpToTab,
      title: 'Jump to tab 1–9',
      description: 'Activate the Nth tab',
      keys: hint([mod, '1–9']),
      keyCaps: [mod, '1–9'],
      section: 'TABS',
    ),
    // PANELS
    ShortcutCatalogEntry(
      action: AppShortcutAction.newPanel,
      title: 'New panel',
      description: 'Create a new panel (workspace)',
      keys: hint([mod, shift, 'N']),
      keyCaps: [mod, shift, 'N'],
      section: 'PANELS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.nextPanel,
      title: 'Next panel',
      description: 'Cycle to the next panel',
      keys: hint([mod, shift, ']']),
      keyCaps: [mod, shift, ']'],
      section: 'PANELS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.prevPanel,
      title: 'Previous panel',
      description: 'Cycle to the previous panel',
      keys: hint([mod, shift, '[']),
      keyCaps: [mod, shift, '['],
      section: 'PANELS',
    ),
    ShortcutCatalogEntry(
      action: AppShortcutAction.jumpToPanel,
      title: 'Jump to panel 1–9',
      description: 'Activate the Nth panel',
      keys: hint([mod, shift, '1–9']),
      keyCaps: [mod, shift, '1–9'],
      section: 'PANELS',
    ),
    // HELP
    ShortcutCatalogEntry(
      action: AppShortcutAction.shortcutsHelp,
      title: 'Keyboard shortcuts',
      description: 'Show the shortcuts cheat-sheet',
      keys: hint([mod, '/']),
      keyCaps: [mod, '/'],
      section: 'HELP',
    ),
  ];
}

/// Compact per-platform hint for [action] — '⌘⇧T' when [useMeta], else
/// 'Ctrl+Shift+T'. For tooltip suffixes ("Send — ⌘↩") and menu labels.
String shortcutHint(AppShortcutAction action, {required bool useMeta}) =>
    shortcutCatalog(
      useMeta: useMeta,
    ).firstWhere((e) => e.action == action).keys;

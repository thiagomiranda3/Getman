// Intent classes for every global keyboard shortcut wired in main.dart's
// appShortcuts map (new/close/send/save/beautify tab, command palette,
// environment switcher, tab/panel navigation + jump-to-index, focus URL).
// Pure markers with no logic; the matching Actions live in MainScreen or
// deeper, wherever their dependencies are reachable (see
// docs/architecture/app-shell.md).

import 'package:flutter/widgets.dart';

class NewTabIntent extends Intent {
  const NewTabIntent();
}

class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

class SendRequestIntent extends Intent {
  const SendRequestIntent();
}

class SaveRequestIntent extends Intent {
  const SaveRequestIntent();
}

class BeautifyJsonIntent extends Intent {
  const BeautifyJsonIntent();
}

class CommandPaletteIntent extends Intent {
  const CommandPaletteIntent();
}

/// Open the quick environment switcher overlay. Bound to Cmd/Ctrl+E.
class SwitchEnvironmentIntent extends Intent {
  const SwitchEnvironmentIntent();
}

/// Activate the next tab (wraps around). Bound to Ctrl+Tab.
class NextTabIntent extends Intent {
  const NextTabIntent();
}

/// Activate the previous tab (wraps around). Bound to Ctrl+Shift+Tab.
class PrevTabIntent extends Intent {
  const PrevTabIntent();
}

/// Jump to the tab at [index] (0-based). Bound to Cmd/Ctrl+1..9.
class JumpToTabIntent extends Intent {
  const JumpToTabIntent(this.index);
  final int index;
}

/// Focus the active tab's URL field. Bound to Cmd/Ctrl+L.
class FocusUrlIntent extends Intent {
  const FocusUrlIntent();
}

/// Create a new panel (Cmd/Ctrl+Shift+N).
class NewPanelIntent extends Intent {
  const NewPanelIntent();
}

/// Activate the next panel, wrapping (Cmd/Ctrl+Shift+]).
class NextPanelIntent extends Intent {
  const NextPanelIntent();
}

/// Activate the previous panel, wrapping (Cmd/Ctrl+Shift+[).
class PrevPanelIntent extends Intent {
  const PrevPanelIntent();
}

/// Jump to the panel at [panelIndex] (0-based) (Cmd/Ctrl+Shift+1..9).
class JumpToPanelIntent extends Intent {
  const JumpToPanelIntent(this.panelIndex);
  final int panelIndex;
}

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

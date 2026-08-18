// Global ScaffoldMessenger key, wired into MaterialApp.router's
// scaffoldMessengerKey in main.dart. Exists for the widget-layer coordinators
// that mount ABOVE MaterialApp (BranchSyncListener, WorkspaceSyncListener):
// ScaffoldMessenger.maybeOf(context) is null up there, which silently
// downgraded their user-facing failure snackbars to debugPrint in production.
// Fall back to `appMessengerKey.currentState` after a null maybeOf.
import 'package:flutter/material.dart';

/// The app's root [ScaffoldMessengerState], usable from contexts that sit
/// above [MaterialApp] in the tree (where `ScaffoldMessenger.maybeOf` finds
/// no ancestor). Null until the first frame builds the MaterialApp — callers
/// must null-check (`?? appMessengerKey.currentState` then guard).
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'appMessenger');

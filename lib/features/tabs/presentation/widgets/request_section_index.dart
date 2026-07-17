// Workspace-global ValueNotifier<int> for the selected request-editor
// section (PARAMS/AUTH/HEADERS/BODY/RULES); see the class doc for details.
import 'package:flutter/foundation.dart';

/// Session-global selected index of the request-editor section strip
/// (PARAMS / AUTH / HEADERS / BODY / RULES).
///
/// The selection is a workspace-level view preference, not per-request state:
/// picking BODY in one request tab means every request tab shows BODY until
/// the user picks another section. Each `RequestConfigSection` /
/// `UnifiedRequestPanel` instance keeps its own `TabController` two-way
/// synced with this notifier (up to `kMaxLiveTabViews` live views exist at
/// once in the tab content stack), and newly-mounted instances seed their
/// initial index from it.
///
/// Only the five section indices (0–4) are ever stored here — the phone
/// layout's extra RESPONSE tab is layout-specific and excluded from the
/// shared selection. Not persisted; resets to PARAMS on app restart.
///
/// Registered as a GetIt lazy singleton and exposed to the widget tree via
/// `ChangeNotifierProvider.value` in `main.dart` (same pattern as
/// `WorkspacePulseController`).
class RequestSectionIndex extends ValueNotifier<int> {
  RequestSectionIndex() : super(0);
}

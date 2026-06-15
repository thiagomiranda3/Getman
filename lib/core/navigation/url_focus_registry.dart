import 'package:flutter/widgets.dart';
import 'package:getman/features/tabs/presentation/widgets/url_bar.dart'
    show UrlBar;

/// Lets a global keyboard shortcut (Cmd/Ctrl+L) focus the active tab's URL
/// field without the dispatcher (`MainScreen`) holding a reference to the
/// deeply-nested [UrlBar].
///
/// Up to `kMaxLiveTabViews` request views are kept alive at once
/// (`TabContentStack`), so each [UrlBar] registers its [FocusNode] keyed by tab
/// id. The focus action resolves the *active* id (known to `MainScreen`) and
/// focuses that node — inactive views are wrapped in `ExcludeFocus`, so even a
/// stray request would be a no-op.
class UrlFocusRegistry {
  final Map<String, FocusNode> _byTab = {};

  /// Associates [tabId] with [node]. Overwrites any prior node for the id.
  void register(String tabId, FocusNode node) => _byTab[tabId] = node;

  /// Drops [tabId]'s node, but only if [node] is still the registered one — a
  /// new [UrlBar] for the same id may have registered before the old one's
  /// dispose runs.
  void unregister(String tabId, FocusNode node) {
    if (identical(_byTab[tabId], node)) _byTab.remove(tabId);
  }

  /// Requests focus for [tabId]'s URL field. No-op when nothing is registered
  /// for the id (e.g. the view was evicted from the live set).
  void focus(String tabId) => _byTab[tabId]?.requestFocus();
}

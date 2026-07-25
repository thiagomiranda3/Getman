// Pure data assembly for the desktop open-tabs dropdown (D1): groups every
// open tab by its owning panel (display order preserved) and filters by a
// search query matching tab title, HTTP method, or URL. Widget-free on
// purpose so grouping/filtering is unit-testable. The compact-phone
// TabSwitcherSheet builds its flat active-panel-only list inline and
// intentionally does not use this helper (D1 leaves the sheet untouched).

import 'package:equatable/equatable.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

/// One dropdown section: a panel plus the (query-filtered) tabs it owns.
class OpenTabGroup extends Equatable {
  const OpenTabGroup({required this.panel, required this.tabs});
  final PanelEntity panel;
  final List<HttpRequestTabEntity> tabs;

  @override
  List<Object?> get props => [panel, tabs];
}

/// Groups all open tabs by panel (panel display order preserved) and filters
/// them with a case-insensitive contains match on the tab's display title,
/// HTTP method, or URL. An empty (or whitespace-only) [query] keeps every
/// tab. Panels left with no matching tabs are omitted.
List<OpenTabGroup> filterOpenTabGroups(
  List<PanelEntity> panels,
  String query,
) {
  final q = query.trim().toLowerCase();
  final groups = <OpenTabGroup>[];
  for (final panel in panels) {
    final tabs = q.isEmpty
        ? panel.tabs
        : panel.tabs
              .where(
                (t) =>
                    t.displayTitle.toLowerCase().contains(q) ||
                    t.config.method.toLowerCase().contains(q) ||
                    t.config.url.toLowerCase().contains(q),
              )
              .toList();
    if (tabs.isNotEmpty) {
      groups.add(OpenTabGroup(panel: panel, tabs: tabs));
    }
  }
  return groups;
}

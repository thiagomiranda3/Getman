// String constants for every Hive box name used across the app (see
// docs/architecture/persistence-hive.md for the typeId <-> box mapping);
// avoids hardcoding box-name literals at each open/watch call site.

class HiveBoxes {
  HiveBoxes._();

  static const String settings = 'settings';
  static const String tabs = 'tabs';

  /// Untyped companion box for [tabs]: stores the explicit tab order as a
  /// `List<String>` of tabIds under the key `'order'` (Hive primitive, no
  /// adapter needed).
  static const String tabsMeta = 'tabs_meta';
  static const String history = 'history';
  static const String collections = 'collections';
  static const String environments = 'environments';
  static const String cookies = 'cookies';
  static const String requestRules = 'request_rules';

  /// Panel structure (typeId 12). Tab entities stay in [tabs]; this box stores
  /// only `{id, name, orderedTabIds, activeTabId}`. Order + active panel live
  /// in [tabsMeta] under `panelOrder` / `activePanelId`.
  static const String panels = 'panels';
}

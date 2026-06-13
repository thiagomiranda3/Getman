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
}

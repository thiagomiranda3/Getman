import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_boxes.dart';

void main() {
  test('box names are stable persisted identifiers', () {
    // These strings name on-disk Hive boxes: renaming any of them would
    // silently orphan users' saved data on upgrade. Pin them exactly.
    expect(HiveBoxes.settings, 'settings');
    expect(HiveBoxes.tabs, 'tabs');
    expect(HiveBoxes.tabsMeta, 'tabs_meta');
    expect(HiveBoxes.history, 'history');
    expect(HiveBoxes.collections, 'collections');
    expect(HiveBoxes.environments, 'environments');
    expect(HiveBoxes.cookies, 'cookies');
    expect(HiveBoxes.requestRules, 'request_rules');
    expect(HiveBoxes.panels, 'panels');
  });

  test('box names never collide', () {
    const names = [
      HiveBoxes.settings,
      HiveBoxes.tabs,
      HiveBoxes.tabsMeta,
      HiveBoxes.history,
      HiveBoxes.collections,
      HiveBoxes.environments,
      HiveBoxes.cookies,
      HiveBoxes.requestRules,
      HiveBoxes.panels,
    ];
    expect(names.toSet().length, names.length);
  });
}

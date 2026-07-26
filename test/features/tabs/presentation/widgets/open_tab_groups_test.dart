// Unit tests for filterOpenTabGroups (D1): grouping by panel in display
// order, case-insensitive title/method/URL matching, empty-query
// passthrough, and omission of panels left with no matching tabs.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/widgets/open_tab_groups.dart';

HttpRequestTabEntity _tab(
  String id, {
  String method = 'GET',
  String url = '',
  String? name,
}) => HttpRequestTabEntity(
  tabId: id,
  config: HttpRequestConfigEntity(id: id, method: method, url: url),
  collectionName: name,
);

PanelEntity _panel(String id, String name, List<HttpRequestTabEntity> tabs) =>
    PanelEntity(
      id: id,
      name: name,
      tabs: tabs,
      activeTabId: tabs.isEmpty ? '' : tabs.first.tabId,
    );

void main() {
  final main_ = _panel('p1', 'Main', [
    _tab('t1', url: 'https://a.dev/users', name: 'ListUsers'),
  ]);
  final work = _panel('p2', 'Work', [
    _tab('t2', method: 'POST', url: 'https://b.dev/orders'),
    _tab('t3'),
  ]);

  test('empty query keeps every panel and every tab, in display order', () {
    final groups = filterOpenTabGroups([main_, work], '');
    expect(groups, hasLength(2));
    expect(groups[0].panel.id, 'p1');
    expect(groups[1].panel.id, 'p2');
    expect(groups[1].tabs.map((t) => t.tabId), ['t2', 't3']);
  });

  test('matches HTTP method case-insensitively and omits empty panels', () {
    final groups = filterOpenTabGroups([main_, work], 'PoSt');
    expect(groups, hasLength(1));
    expect(groups.single.panel.id, 'p2');
    expect(groups.single.tabs.single.tabId, 't2');
  });

  test('matches the display title (collectionName) and the URL', () {
    final byName = filterOpenTabGroups([main_, work], 'listus');
    expect(byName.single.tabs.single.tabId, 't1');

    final byUrl = filterOpenTabGroups([main_, work], 'b.dev/ord');
    expect(byUrl.single.tabs.single.tabId, 't2');
  });

  test('a panel with no tabs is omitted even with an empty query', () {
    final empty = _panel('p3', 'Empty', const []);
    final groups = filterOpenTabGroups([main_, empty], '');
    expect(groups.map((g) => g.panel.id), ['p1']);
  });

  test('whitespace-only query behaves like an empty query', () {
    expect(filterOpenTabGroups([work], '   '), hasLength(1));
  });
}

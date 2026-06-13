import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

void main() {
  HttpRequestTabEntity tab({String? collectionName, String url = ''}) => HttpRequestTabEntity(
        tabId: 't1',
        collectionName: collectionName,
        config: HttpRequestConfigEntity(id: 'c1', url: url),
      );

  group('displayTitle', () {
    test('prefers the saved collection name', () {
      expect(tab(collectionName: 'Login', url: 'https://x.dev').displayTitle, 'Login');
    });

    test('falls back to the URL', () {
      expect(tab(url: 'https://x.dev').displayTitle, 'https://x.dev');
    });

    test('labels unsaved empty tabs NEW REQUEST', () {
      expect(tab().displayTitle, 'NEW REQUEST');
    });
  });

  group('byId', () {
    test('finds a tab by id and returns null on miss', () {
      final tabs = [tab(url: 'a')];
      expect(tabs.byId('t1'), tabs.single);
      expect(tabs.byId('ghost'), isNull);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late Box<HttpRequestTabModel> tabsBox;
  late Box<dynamic> metaBox;
  late TabsLocalDataSourceImpl dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_tabs_ds_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(HttpRequestConfigAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(HttpRequestTabModelAdapter());
    }
    tabsBox = await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
    metaBox = await Hive.openBox(HiveBoxes.tabsMeta);
    dataSource = TabsLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  HttpRequestTabModel model(String id) => HttpRequestTabModel(
    config: HttpRequestConfig(id: id, url: 'https://$id.dev'),
    tabId: id,
  );

  group('legacy migration', () {
    test(
      're-keys an int-keyed box by tabId preserving insertion order',
      () async {
        // Legacy layout: auto-increment int keys from box.addAll.
        await tabsBox.addAll([model('a'), model('b'), model('c')]);
        expect(tabsBox.keys.every((k) => k is int), isTrue);

        final tabs = await dataSource.getTabs();

        expect(tabs.map((t) => t.tabId), ['a', 'b', 'c']);
        expect(tabsBox.keys.toSet(), {'a', 'b', 'c'});
        expect(metaBox.get(TabsLocalDataSourceImpl.orderKey), ['a', 'b', 'c']);
      },
    );

    test('does not rewrite a box already keyed by tabId', () async {
      await dataSource.putTab(model('a'));
      await dataSource.saveOrder(['a']);

      final tabs = await dataSource.getTabs();

      expect(tabs.map((t) => t.tabId), ['a']);
      expect(tabsBox.keys.toSet(), {'a'});
    });
  });

  group('order reconciliation', () {
    test(
      'drops order entries whose tab no longer exists and appends unknown tabs',
      () async {
        await tabsBox.putAll({
          'a': model('a'),
          'b': model('b'),
          'c': model('c'),
        });
        // 'ghost' has no box entry; 'b' is in the box but missing from the
        // order.
        await metaBox.put(TabsLocalDataSourceImpl.orderKey, [
          'c',
          'ghost',
          'a',
        ]);

        final tabs = await dataSource.getTabs();

        expect(tabs.map((t) => t.tabId), ['c', 'a', 'b']);
      },
    );

    test('returns all box entries when no order was ever saved', () async {
      await tabsBox.putAll({'a': model('a'), 'b': model('b')});

      final tabs = await dataSource.getTabs();

      expect(tabs.map((t) => t.tabId).toSet(), {'a', 'b'});
    });
  });

  group('incremental writes', () {
    test('putTab, saveOrder and deleteTabs round-trip', () async {
      await dataSource.putTab(model('a'));
      await dataSource.putTab(model('b'));
      await dataSource.saveOrder(['b', 'a']);

      expect((await dataSource.getTabs()).map((t) => t.tabId), ['b', 'a']);

      await dataSource.deleteTabs(['a']);

      expect(tabsBox.get('a'), isNull);
      expect((await dataSource.getTabs()).map((t) => t.tabId), ['b']);
    });

    test('putTab overwrites the existing entry for the same tabId', () async {
      await dataSource.putTab(model('a'));
      final updated = HttpRequestTabModel(
        config: HttpRequestConfig(id: 'a', url: 'https://edited.dev'),
        tabId: 'a',
      );
      await dataSource.putTab(updated);

      expect(tabsBox.length, 1);
      expect(tabsBox.get('a')!.config.url, 'https://edited.dev');
    });

    test(
      'saveTabs rewrites the whole box keyed by tabId plus the order',
      () async {
        await dataSource.putTab(model('stale'));
        await dataSource.saveTabs([model('a'), model('b')]);

        expect(tabsBox.keys.toSet(), {'a', 'b'});
        expect(metaBox.get(TabsLocalDataSourceImpl.orderKey), ['a', 'b']);
        expect((await dataSource.getTabs()).map((t) => t.tabId), ['a', 'b']);
      },
    );
  });
}

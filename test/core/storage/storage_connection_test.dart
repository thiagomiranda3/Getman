// Real native worker regressions: existing Hive bytes, subscription ordering,
// shutdown durability, legacy migrations and failures without poisoned queues.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/background_repositories.dart';
import 'package:getman/core/storage/hive_adapters.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/core/storage/storage_connection.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory directory;
  StorageConnection? connection;
  const config = HttpRequestConfigEntity(
    id: 'request',
    url: 'https://api.test',
  );
  const tab = HttpRequestTabEntity(config: config, tabId: 'tab');

  Future<StorageConnection> open() async => connection =
      await openStorageConnection('${directory.path}/settings.hive');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('getman_storage_worker');
    Hive.init(directory.path);
    registerHiveAdapters();
  });
  tearDown(() async {
    await connection?.close();
    connection = null;
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'legacy boxes migrate in the owner and remain readable after restart',
    () async {
      final environments = await Hive.openBox<EnvironmentModel>(
        HiveBoxes.environments,
      );
      final env = EnvironmentEntity(
        id: 'env',
        name: 'Legacy',
        variables: const {'token': 'secret'},
      );
      await environments.add(EnvironmentModel.fromEntity(env));
      final collections = await Hive.openBox<CollectionNode>(
        HiveBoxes.collections,
      );
      const root = CollectionNodeEntity(id: 'root', name: 'Legacy collection');
      await collections.add(CollectionNode.fromEntity(root));
      final tabs = await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
      await tabs.add(HttpRequestTabModel.fromEntity(tab));
      final cookies = await Hive.openBox<StoredCookieModel>(HiveBoxes.cookies);
      const cookie = NetworkCookie(
        name: 'sid',
        value: 'old',
        domain: 'api.test',
      );
      await cookies.add(StoredCookieModel.fromCookie(cookie));
      await Hive.close();

      var worker = await open();
      expect(await BackgroundEnvironmentsRepository(worker).getEnvironments(), [
        env,
      ]);
      expect(await BackgroundCollectionsRepository(worker).getCollections(), [
        root,
      ]);
      final panels = await BackgroundTabsPersistence(worker).getPanels();
      expect(panels.single.tabs, [tab]);
      expect(
        await worker.invoke<List<NetworkCookie>>(StorageOperation.cookiesGet),
        [cookie],
      );
      for (final name in [
        HiveBoxes.tabs,
        HiveBoxes.collections,
        HiveBoxes.environments,
        HiveBoxes.cookies,
      ]) {
        expect(Hive.isBoxOpen(name), isFalse, reason: 'UI never opens $name');
      }
      await worker.close();
      worker = await open();
      expect(await BackgroundTabsPersistence(worker).getTabs(), [tab]);
      expect(await BackgroundEnvironmentsRepository(worker).getEnvironments(), [
        env,
      ]);
      await worker.close();
      final migrated = await Hive.openBox<EnvironmentModel>(
        HiveBoxes.environments,
      );
      expect(migrated.keys, ['env']);
      expect(migrated.get('env')!.toEntity(), env);
    },
  );

  test(
    'queued writes drain on close, with caps and no transient media data',
    () async {
      var worker = await open();
      final tabs = BackgroundTabsPersistence(worker);
      final response = HttpResponseEntity(
        statusCode: 200,
        body: 'x' * (kMaxPersistedResponseBodyChars + 1),
        headers: const {},
        durationMs: 1,
        bodyBytes: Uint8List(2 * 1024 * 1024),
      );
      final write = tabs.putTab(tab.copyWith(response: response));
      final panel = tabs.putPanel(
        const PanelEntity(
          id: 'panel',
          name: 'Panel',
          tabs: [tab],
          activeTabId: 'tab',
        ),
      );
      final meta = tabs.savePanelMeta(['panel'], 'panel');
      await worker.close();
      await Future.wait([write, panel, meta]);
      worker = await open();
      final reopened = BackgroundTabsPersistence(worker);
      final loaded = (await reopened.getTabs()).single;
      expect(loaded.response!.body, kResponseBodyTooLargePlaceholder);
      expect(loaded.response!.bodyBytes, isNull);
      expect(response.bodyBytes, hasLength(2 * 1024 * 1024));
      expect((await reopened.getPanels()).single.activeTabId, 'tab');
      expect(await reopened.getActivePanelId(), 'panel');
    },
  );

  test(
    'watchers deliver initial and committed values, then allow resubscribe',
    () async {
      final worker = await open();
      final environments = BackgroundEnvironmentsRepository(worker);
      final stream = StreamIterator(environments.watchEnvironments());
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);
      final env = EnvironmentEntity(
        id: 'env',
        name: 'Production',
        variables: const {'keep': 'yes'},
      );
      await environments.putEnvironment(env);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, [env]);
      await stream.cancel();
      await environments.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'token': 'captured'}),
      );
      await environments.updateEnvironment(
        env.copyWith(name: 'Renamed'),
        previous: env,
      );
      final restored = await environments.watchEnvironments().first;
      expect(restored.single.name, 'Renamed');
      expect(restored.single.variables, {'keep': 'yes', 'token': 'captured'});
      await environments.deleteEnvironment('env');
      await expectLater(
        environments.applyVariablePatch(
          'env',
          ScriptPatch(sets: const {'x': 'y'}),
        ),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await environments.getEnvironments(), isEmpty);
    },
  );

  test(
    'history dedup, undo, dictionary and script trust survive the RPC boundary',
    () async {
      final worker = await open();
      final history = BackgroundHistoryRepository(worker);
      await history.addToHistory(config, 10);
      await history.addToHistory(config, 10);
      final snapshot = await history.watchHistory().first;
      expect(snapshot, hasLength(1));
      expect(snapshot.single.id, isNot(config.id));
      await history.deleteHistoryEntry(snapshot.single.id);
      expect(await history.watchHistory().first, isEmpty);
      await history.restoreHistoryEntries(snapshot);
      expect(await history.watchHistory().first, snapshot);
      final dictionary = BackgroundBodyFieldDictionary(worker, const []);
      await Future.wait([
        dictionary.recordUsage({'email': 2}),
        dictionary.recordUsage({'email': 3}),
      ]);
      expect(dictionary.entries, const [
        BodyFieldEntry(name: 'email', usageCount: 5),
      ]);
      final trust = BackgroundScriptTrustRepository(worker);
      const scripts = RequestScripts(preRequest: 'gm.log("approved");');
      expect(await trust.isTrusted('request', scripts), isFalse);
      await trust.trust('request', scripts);
      expect(await trust.isTrusted('request', scripts), isTrue);
      expect(
        await trust.isTrusted(
          'request',
          scripts.copyWith(preRequest: 'changed'),
        ),
        isFalse,
      );
    },
  );

  test(
    'failed operations do not poison the queue; a second owner is rejected',
    () async {
      final worker = await open();
      await expectLater(
        openStorageConnection('${directory.path}/settings.hive'),
        throwsStateError,
      );
      await expectLater(
        worker.invoke<void>(StorageOperation.tabsSave, 'invalid'),
        throwsA(isA<PersistenceFailure>()),
      );
      final tabs = BackgroundTabsPersistence(worker);
      await tabs.putTab(tab);
      expect(await tabs.getTabs(), [tab]);
      await worker.close();
      await expectLater(tabs.getTabs(), throwsA(isA<PersistenceFailure>()));
    },
  );

  test(
    'worker refuses feature boxes already owned by the caller',
    () async {
      final tabs = await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
      await tabs.put('tab', HttpRequestTabModel.fromEntity(tab));
      await expectLater(open(), throwsStateError);
      expect(tabs.isOpen, isTrue);
      await tabs.close();
      final worker = await open();
      expect(await BackgroundTabsPersistence(worker).getTabs(), [tab]);
    },
  );

  test(
    'startup failure releases ownership and reports instead of hanging',
    () async {
      final obstruction = Directory('${directory.path}/history.hive');
      await obstruction.create();
      await expectLater(
        open().timeout(const Duration(seconds: 10)),
        throwsA(isA<PersistenceFailure>()),
      );
      await obstruction.delete();
      final worker = await open();
      expect(await BackgroundTabsPersistence(worker).getTabs(), isEmpty);
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/network/in_memory_cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/chaining/data/models/assertion_model.dart';
import 'package:getman/features/chaining/data/models/extraction_rule_model.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:getman/features/cookies/data/hive_cookie_persistence.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:hive_ce/hive.dart';

/// Guards the cold-start ordering behind bugs #1/#2: the cookies + request-rules
/// boxes must be opened and the cookie jar hydrated on the boot path, not after
/// the first frame — otherwise an early send drops persisted cookies and skips
/// post-response rules.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_boot_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(StoredCookieModelAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ExtractionRuleModelAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(AssertionModelAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(RequestRulesModelAdapter());
    }
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test(
    'opens both deferred boxes and hydrates the jar from a cold (closed) state',
    () async {
      // Persist a cookie, then close the box to simulate "app not yet booted".
      final seed = await Hive.openBox<StoredCookieModel>(HiveBoxes.cookies);
      await seed.put(
        'api.dev|/|sid',
        StoredCookieModel.fromCookie(
          const NetworkCookie(name: 'sid', value: 'abc', domain: 'api.dev'),
        ),
      );
      await seed.close();
      expect(Hive.isBoxOpen(HiveBoxes.cookies), isFalse);

      final store = InMemoryCookieStore(persistence: HiveCookiePersistence());
      await di.openAndHydrateDeferredBoxes(store);

      expect(
        Hive.isBoxOpen(HiveBoxes.cookies),
        isTrue,
        reason: 'cookies box must be opened on the cold-start path',
      );
      expect(
        Hive.isBoxOpen(HiveBoxes.requestRules),
        isTrue,
        reason: 'request-rules box must be opened on the cold-start path',
      );
      // Hydration ran, so the persisted cookie is sent on a matching request —
      // this is exactly what an early send dropped before the fix.
      final header = store.cookieHeaderFor(Uri.parse('https://api.dev/users'));
      expect(header, contains('sid=abc'));
    },
  );

  test('is idempotent when the boxes are already open', () async {
    await Hive.openBox<StoredCookieModel>(HiveBoxes.cookies);
    await Hive.openBox<RequestRulesModel>(HiveBoxes.requestRules);
    final store = InMemoryCookieStore(persistence: HiveCookiePersistence());

    await di.openAndHydrateDeferredBoxes(store); // must not throw

    expect(Hive.isBoxOpen(HiveBoxes.cookies), isTrue);
    expect(Hive.isBoxOpen(HiveBoxes.requestRules), isTrue);
  });
}

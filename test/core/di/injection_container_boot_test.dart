// Boot the production storage path with persisted cookies. The themed gate
// must not expose send controls before hydration; only the worker owns the jar.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/hive_adapters.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_boot_test');
    Hive.init(tempDir.path);
    registerHiveAdapters();
  });

  tearDown(() async {
    await di.reset();
    await tempDir.delete(recursive: true);
  });

  test('first usable jar contains cookies from the previous launch', () async {
    final seed = await Hive.openBox<StoredCookieModel>(HiveBoxes.cookies);
    await seed.put(
      'api.dev|/|sid',
      StoredCookieModel.fromCookie(
        const NetworkCookie(name: 'sid', value: 'abc', domain: 'api.dev'),
      ),
    );
    await seed.close();
    final settings = await di.initSettings(
      storageDirectoryOverride: tempDir.path,
    );
    expect(di.sl.isRegistered<CookieStore>(), isFalse);
    await di.initServices(settings);
    expect(Hive.isBoxOpen(HiveBoxes.cookies), isFalse);
    expect(
      di.sl<CookieStore>().cookieHeaderFor(Uri.parse('https://api.dev/users')),
      contains('sid=abc'),
    );
    expect(Hive.isBoxOpen('request_rules'), isFalse);
  });

  test('cookie writes drain on shutdown and hydrate on next boot', () async {
    await di.init(storageDirectoryOverride: tempDir.path);
    di.sl<CookieStore>().storeFromSetCookie(
      Uri.parse('https://api.dev'),
      'sid=new; Path=/',
    );
    // Writes are fire-and-forget at the interceptor; shutdown must drain them.
    await di.reset();
    await di.init(storageDirectoryOverride: tempDir.path);
    expect(di.sl<CookieStore>().all().single.value, 'new');
    await di.sl<CookieStore>().clear();
    await di.reset();
    await di.init(storageDirectoryOverride: tempDir.path);
    expect(di.sl<CookieStore>().all(), isEmpty);
  });
}

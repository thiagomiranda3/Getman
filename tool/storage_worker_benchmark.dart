// Opt-in scheduling benchmark. Run with:
// fvm flutter test --no-pub tool/storage_worker_benchmark.dart --reporter expanded
// Measures Dart event-loop gaps, not rendered frame times or process startup.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/storage/background_repositories.dart';
import 'package:getman/core/storage/hive_adapters.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/core/storage/storage_connection.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/repositories/hive_tabs_persistence.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:hive_ce/hive.dart';

Future<Map<String, Object>> measure(
  String name,
  Future<void> Function() work,
) async {
  final clock = Stopwatch()..start();
  var last = 0;
  var maxGap = 0;
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = clock.elapsedMicroseconds;
    final gap = now - last;
    if (gap > maxGap) maxGap = gap;
    last = now;
    ticks++;
  });
  await Future<void>.delayed(const Duration(milliseconds: 10));
  last = clock.elapsedMicroseconds;
  maxGap = 0;
  ticks = 0;
  final elapsed = Stopwatch()..start();
  try {
    await work();
    elapsed.stop();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  } finally {
    timer.cancel();
  }
  return {
    'case': name,
    'elapsedMs': elapsed.elapsedMicroseconds / 1000,
    'maxEventLoopGapMs': maxGap / 1000,
    'heartbeatTicks': ticks,
  };
}

void main() {
  test(
    'compare local Hive with the persistent worker using the same bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'getman_storage_benchmark',
      );
      registerHiveAdapters();
      Hive.init(dir.path);
      final body = 'x' * (128 * 1024);
      final tabs = List.generate(
        500,
        (i) => HttpRequestTabEntity(
          tabId: 'tab-$i',
          config: HttpRequestConfigEntity(id: 'request-$i'),
          response: HttpResponseEntity(
            statusCode: 200,
            body: body,
            headers: const {},
            durationMs: 1,
          ),
        ),
      );
      final seed = await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
      await seed.putAll({
        for (final tab in tabs) tab.tabId: HttpRequestTabModel.fromEntity(tab),
      });
      await Hive.close();
      final results = <Map<String, Object>>[];
      try {
        // Alternate ordering to reduce cache/order bias; this remains a warm-disk,
        // debug/JIT microbenchmark, not a claim about release startup latency.
        for (var round = 0; round < 3; round++) {
          for (final background
              in round.isEven ? [false, true] : [true, false]) {
            results.add(
              await measure(background ? 'worker' : 'local', () async {
                if (background) {
                  final connection = await openStorageConnection(
                    '${dir.path}/settings.hive',
                  );
                  try {
                    expect(
                      await BackgroundTabsPersistence(connection).getTabs(),
                      hasLength(500),
                    );
                  } finally {
                    await connection.close();
                  }
                } else {
                  await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
                  await Hive.openBox<dynamic>(HiveBoxes.tabsMeta);
                  expect(
                    await HiveTabsPersistence(
                      TabsLocalDataSourceImpl(),
                    ).getTabs(),
                    hasLength(500),
                  );
                  await Hive.close();
                }
              }),
            );
          }
        }
        debugPrint(
          const JsonEncoder.withIndent('  ').convert({
            'tabs': tabs.length,
            'responseBytesPerTab': body.length,
            'mode':
                'flutter test debug/JIT; warm filesystem; no widget rendering',
            'results': results,
          }),
        );
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

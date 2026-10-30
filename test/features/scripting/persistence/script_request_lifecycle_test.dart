import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:hive_ce/hive.dart';

void main() {
  const scripts = RequestScripts(
    apiVersion: 99,
    preRequest: 'const token = "ação";',
    postResponse: 'gm.test("ok", () => {});',
    preRequestEnabled: false,
    postResponseEnabled: false,
  );
  test(
    'scripts survive copy, duplicate, dirty tracking and history signature',
    () {
      const original = HttpRequestConfigEntity(id: 'request');
      final edited = original.copyWith(scripts: scripts);
      expect(edited, isNot(original));
      expect(edited.copyWith(method: 'POST').scripts, scripts);
      expect(edited.withId('duplicate').scripts, scripts);
      expect(edited.withId('duplicate').id, 'duplicate');
      expect(
        HttpRequestConfig.fromEntity(original),
        isNot(HttpRequestConfig.fromEntity(edited)),
      );
      const checker = TabDirtyChecker();
      final tab = HttpRequestTabEntity(tabId: 'tab', config: edited);
      expect(checker(tab: tab, savedConfigs: const {}), isTrue);
      expect(
        checker(
          tab: tab.copyWith(config: original),
          savedConfigs: const {},
        ),
        isFalse,
      );
    },
  );
  test('every script field participates in history dedup', () {
    const original = HttpRequestConfigEntity(id: 'request');
    final baseline = HttpRequestConfig.fromEntity(original);
    for (final changed in [
      const RequestScripts(preRequest: 'before();'),
      const RequestScripts(postResponse: 'after();'),
      const RequestScripts(preRequestEnabled: false),
      const RequestScripts(postResponseEnabled: false),
      const RequestScripts(apiVersion: 2),
    ]) {
      expect(
        HttpRequestConfig.fromEntity(original.copyWith(scripts: changed)),
        isNot(baseline),
      );
    }
    final legacyEmpty = HttpRequestConfig(id: 'other');
    expect(legacyEmpty, baseline);
    expect(legacyEmpty.hashCode, baseline.hashCode);
  });
  test('legacy schema without field 19 reads as empty scripts', () async {
    final directory = await Directory.systemTemp.createTemp('getman-legacy-');
    Hive
      ..init(directory.path)
      ..registerAdapter(_LegacyRequestAdapter(), override: true);
    try {
      final legacy = await Hive.openBox<HttpRequestConfig>('legacy');
      await legacy.put('request', HttpRequestConfig(id: 'legacy'));
      await legacy.close();
      Hive.registerAdapter(HttpRequestConfigAdapter(), override: true);
      final reopened = await Hive.openBox<HttpRequestConfig>('legacy');
      expect(
        reopened.get('request')!.toEntity().scripts,
        const RequestScripts(),
      );
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
  test(
    'Hive restart preserves disabled sources and unknown API version',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'getman-scripts-',
      );
      Hive
        ..init(directory.path)
        ..registerAdapter(HttpRequestConfigAdapter(), override: true);
      try {
        final box = await Hive.openBox<HttpRequestConfig>('requests');
        await box.put(
          'request',
          HttpRequestConfig.fromEntity(
            const HttpRequestConfigEntity(id: 'request', scripts: scripts),
          ),
        );
        await box.flush();
        await box.close();
        final reopened = await Hive.openBox<HttpRequestConfig>('requests');
        expect(reopened.get('request')!.toEntity().scripts, scripts);
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

// Writes the frozen pre-scripts schema, independent from the current adapter.
class _LegacyRequestAdapter extends TypeAdapter<HttpRequestConfig> {
  @override
  int get typeId => 1;

  @override
  HttpRequestConfig read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, HttpRequestConfig obj) {
    final fields = <Object?>[
      obj.id,
      'GET',
      '',
      <String, String>{},
      <String, String>{},
      '',
      <String, String>{},
      null,
      null,
      null,
      null,
      'raw',
      <Object>[],
      null,
      0,
      '',
      <Object>[],
      <String>[],
      null,
    ];
    writer.writeByte(fields.length);
    for (var i = 0; i < fields.length; i++) {
      writer
        ..writeByte(i)
        ..write(fields[i]);
    }
  }
}

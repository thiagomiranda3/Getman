import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

void main() {
  group('SettingsModel themeId', () {
    test('fromEntity default themeId is brutalist', () {
      final model = SettingsModel.fromEntity(const SettingsEntity());
      expect(model.themeId, 'brutalist');
    });

    test('json roundtrip preserves themeId', () {
      final model = SettingsModel(themeId: 'editorial');
      final roundTripped = SettingsModel.fromJson(model.toJson());
      expect(roundTripped.themeId, 'editorial');
    });

    test('entity roundtrip preserves themeId', () {
      const entity = SettingsEntity(themeId: 'editorial');
      final model = SettingsModel.fromEntity(entity);
      expect(model.toEntity().themeId, 'editorial');
    });

    test('copyWith overrides themeId but keeps other fields', () {
      final original = SettingsModel(historyLimit: 50);
      final copy = original.copyWith(themeId: 'editorial');
      expect(copy.themeId, 'editorial');
      expect(copy.historyLimit, 50);
    });
  });

  group('SettingsModel activeEnvironmentId', () {
    test('default is null', () {
      expect(const SettingsEntity().activeEnvironmentId, isNull);
      expect(SettingsModel().activeEnvironmentId, isNull);
    });

    test('entity roundtrip preserves a set id', () {
      const entity = SettingsEntity(activeEnvironmentId: 'env-42');
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.activeEnvironmentId, 'env-42');
    });

    test('entity roundtrip preserves null', () {
      const entity = SettingsEntity();
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.activeEnvironmentId, isNull);
    });

    test('json roundtrip preserves id', () {
      final model = SettingsModel(activeEnvironmentId: 'x');
      expect(SettingsModel.fromJson(model.toJson()).activeEnvironmentId, 'x');
    });

    test('SettingsEntity.copyWith can clear to null explicitly', () {
      const entity = SettingsEntity(activeEnvironmentId: 'x');
      final cleared = entity.copyWith(activeEnvironmentId: null);
      expect(cleared.activeEnvironmentId, isNull);
    });

    test('SettingsEntity.copyWith without arg preserves previous id', () {
      const entity = SettingsEntity(activeEnvironmentId: 'x');
      final preserved = entity.copyWith(themeId: 'other');
      expect(preserved.activeEnvironmentId, 'x');
    });
  });

  group('SettingsModel network + workspace fields', () {
    test('defaults match the network baseline', () {
      const e = SettingsEntity();
      expect(e.connectTimeoutMs, 30000);
      expect(e.sendTimeoutMs, 30000);
      expect(e.receiveTimeoutMs, 60000);
      expect(e.followRedirects, isTrue);
      expect(e.maxRedirects, 5);
      expect(e.verifySsl, isTrue);
      expect(e.proxyUrl, isNull);
      expect(e.workspacePath, isNull);
    });

    test('json roundtrip preserves the new fields', () {
      final model = SettingsModel(
        connectTimeoutMs: 1000,
        sendTimeoutMs: 2000,
        receiveTimeoutMs: 3000,
        followRedirects: false,
        maxRedirects: 2,
        verifySsl: false,
        proxyUrl: 'localhost:8888',
        workspacePath: '/tmp/ws',
      );
      final back = SettingsModel.fromJson(model.toJson());
      expect(back.connectTimeoutMs, 1000);
      expect(back.sendTimeoutMs, 2000);
      expect(back.receiveTimeoutMs, 3000);
      expect(back.followRedirects, isFalse);
      expect(back.maxRedirects, 2);
      expect(back.verifySsl, isFalse);
      expect(back.proxyUrl, 'localhost:8888');
      expect(back.workspacePath, '/tmp/ws');
    });

    test('maxRedirects defaults to 5 for legacy json without the field', () {
      final back = SettingsModel.fromJson({'historyLimit': 50});
      expect(back.maxRedirects, 5);
    });

    test('entity roundtrip preserves the new fields', () {
      const entity = SettingsEntity(
        connectTimeoutMs: 5,
        verifySsl: false,
        proxyUrl: 'p:1',
        workspacePath: '/ws',
        clientCertPath: '/c.pem',
        clientKeyPath: '/k.pem',
        clientCertPassphrase: 'secret',
      );
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.connectTimeoutMs, 5);
      expect(back.verifySsl, isFalse);
      expect(back.proxyUrl, 'p:1');
      expect(back.workspacePath, '/ws');
      expect(back.clientCertPath, '/c.pem');
      expect(back.clientKeyPath, '/k.pem');
      expect(back.clientCertPassphrase, 'secret');
    });

    test('json roundtrip preserves the client certificate', () {
      final model = SettingsModel(
        clientCertPath: '/c.pem',
        clientKeyPath: '/k.pem',
        clientCertPassphrase: 'secret',
      );
      final back = SettingsModel.fromJson(model.toJson());
      expect(back.clientCertPath, '/c.pem');
      expect(back.clientKeyPath, '/k.pem');
      expect(back.clientCertPassphrase, 'secret');
    });

    test('toNetworkConfig maps the client certificate', () {
      const entity = SettingsEntity(
        clientCertPath: '/c.pem',
        clientKeyPath: '/k.pem',
        clientCertPassphrase: 'secret',
      );
      final config = entity.toNetworkConfig();
      expect(config.clientCertPath, '/c.pem');
      expect(config.clientKeyPath, '/k.pem');
      expect(config.clientCertPassphrase, 'secret');
    });

    test(
      'copyWith clears proxyUrl / workspacePath / cert fields via the sentinel',
      () {
        const entity = SettingsEntity(
          proxyUrl: 'p:1',
          workspacePath: '/ws',
          clientCertPath: '/c.pem',
          clientKeyPath: '/k.pem',
          clientCertPassphrase: 'secret',
        );
        expect(entity.copyWith(proxyUrl: null).proxyUrl, isNull);
        expect(entity.copyWith(workspacePath: null).workspacePath, isNull);
        expect(entity.copyWith(clientCertPath: null).clientCertPath, isNull);
        expect(entity.copyWith(clientKeyPath: null).clientKeyPath, isNull);
        expect(
          entity.copyWith(clientCertPassphrase: null).clientCertPassphrase,
          isNull,
        );
        // Omitting keeps them.
        final kept = entity.copyWith(verifySsl: false);
        expect(kept.proxyUrl, 'p:1');
        expect(kept.workspacePath, '/ws');
        expect(kept.clientCertPath, '/c.pem');
        expect(kept.clientKeyPath, '/k.pem');
        expect(kept.clientCertPassphrase, 'secret');
      },
    );
  });

  group('SettingsModel reduceVisualEffects', () {
    test('default is false (full effects)', () {
      expect(const SettingsEntity().reduceVisualEffects, isFalse);
      expect(SettingsModel().reduceVisualEffects, isFalse);
    });

    test('json roundtrip preserves the flag', () {
      final model = SettingsModel(reduceVisualEffects: true);
      final back = SettingsModel.fromJson(model.toJson());
      expect(back.reduceVisualEffects, isTrue);
    });

    test('entity roundtrip preserves the flag', () {
      const entity = SettingsEntity(reduceVisualEffects: true);
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.reduceVisualEffects, isTrue);
    });

    test('legacy json without the field defaults to false', () {
      final back = SettingsModel.fromJson({'historyLimit': 50});
      expect(back.reduceVisualEffects, isFalse);
    });

    test('copyWith overrides the flag but keeps other fields', () {
      const original = SettingsEntity(historyLimit: 50);
      final copy = original.copyWith(reduceVisualEffects: true);
      expect(copy.reduceVisualEffects, isTrue);
      expect(copy.historyLimit, 50);
    });
  });

  group('SettingsModel workspaceBookmark (macOS security-scoped bookmark)', () {
    test('default is null', () {
      expect(const SettingsEntity().workspaceBookmark, isNull);
      expect(SettingsModel().workspaceBookmark, isNull);
    });

    test('json roundtrip preserves the bookmark', () {
      final model = SettingsModel(
        workspacePath: '/ws',
        workspaceBookmark: 'Ym9va21hcms=',
      );
      final back = SettingsModel.fromJson(model.toJson());
      expect(back.workspacePath, '/ws');
      expect(back.workspaceBookmark, 'Ym9va21hcms=');
    });

    test('entity roundtrip preserves the bookmark', () {
      const entity = SettingsEntity(
        workspacePath: '/ws',
        workspaceBookmark: 'Ym9va21hcms=',
      );
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.workspaceBookmark, 'Ym9va21hcms=');
    });

    test(
      'copyWith clears the bookmark via the sentinel; omitting keeps it',
      () {
        const entity = SettingsEntity(
          workspacePath: '/ws',
          workspaceBookmark: 'b',
        );
        expect(
          entity.copyWith(workspaceBookmark: null).workspaceBookmark,
          isNull,
        );
        expect(entity.copyWith(verifySsl: false).workspaceBookmark, 'b');
      },
    );
  });

  group('SettingsModel checkForUpdatesOnStartup + skippedUpdateVersion', () {
    test('round-trips checkForUpdatesOnStartup and skippedUpdateVersion', () {
      const entity = SettingsEntity(
        checkForUpdatesOnStartup: false,
        skippedUpdateVersion: '1.2.3',
      );
      final model = SettingsModel.fromEntity(entity);
      expect(model.checkForUpdatesOnStartup, isFalse);
      expect(model.skippedUpdateVersion, '1.2.3');

      final back = model.toEntity();
      expect(back.checkForUpdatesOnStartup, isFalse);
      expect(back.skippedUpdateVersion, '1.2.3');
    });

    test('checkForUpdatesOnStartup defaults to true', () {
      expect(const SettingsEntity().checkForUpdatesOnStartup, isTrue);
      expect(const SettingsEntity().skippedUpdateVersion, isNull);
    });
  });
}

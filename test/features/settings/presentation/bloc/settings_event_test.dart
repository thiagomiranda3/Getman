// Equality/props coverage for every SettingsEvent subclass: two equal
// instances compare equal (== and hashCode), a differing instance does not,
// and every field is exercised (including explicit-null clears on the
// nullable grouped events).

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';

void main() {
  group('UpdateDarkMode', () {
    test('equal instances match; differing isDarkMode does not', () {
      const a = UpdateDarkMode(isDarkMode: true);
      const b = UpdateDarkMode(isDarkMode: true);
      const c = UpdateDarkMode(isDarkMode: false);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.isDarkMode, isTrue);
      expect(a.props, [true]);
    });
  });

  group('UpdateCompactMode', () {
    test('equal instances match; differing isCompactMode does not', () {
      const a = UpdateCompactMode(isCompactMode: true);
      const b = UpdateCompactMode(isCompactMode: true);
      const c = UpdateCompactMode(isCompactMode: false);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(c.isCompactMode, isFalse);
      expect(a.props, [true]);
    });
  });

  group('UpdateVerticalLayout', () {
    test('equal instances match; differing isVerticalLayout does not', () {
      const a = UpdateVerticalLayout(isVerticalLayout: true);
      const b = UpdateVerticalLayout(isVerticalLayout: true);
      const c = UpdateVerticalLayout(isVerticalLayout: false);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.isVerticalLayout, isTrue);
      expect(a.props, [true]);
    });
  });

  group('UpdateHistoryLimit', () {
    test('equal instances match; differing limit does not', () {
      const a = UpdateHistoryLimit(50);
      const b = UpdateHistoryLimit(50);
      const c = UpdateHistoryLimit(10);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.historyLimit, 50);
      expect(a.props, [50]);
    });
  });

  group('UpdateSaveResponseInHistory', () {
    test('equal instances match; differing save does not', () {
      const a = UpdateSaveResponseInHistory(save: true);
      const b = UpdateSaveResponseInHistory(save: true);
      const c = UpdateSaveResponseInHistory(save: false);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.save, isTrue);
      expect(a.props, [true]);
    });
  });

  group('UpdateAlwaysPrettifyLargeResponses', () {
    test('equal instances match; differing value does not', () {
      const a = UpdateAlwaysPrettifyLargeResponses(value: true);
      const b = UpdateAlwaysPrettifyLargeResponses(value: true);
      const c = UpdateAlwaysPrettifyLargeResponses(value: false);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.value, isTrue);
      expect(a.props, [true]);
    });
  });

  group('UpdateResponseHistoryLimit', () {
    test('equal instances match; differing limit does not', () {
      const a = UpdateResponseHistoryLimit(10);
      const b = UpdateResponseHistoryLimit(10);
      const c = UpdateResponseHistoryLimit(0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.limit, 10);
      expect(a.props, [10]);
    });
  });

  group('UpdateSaveLargeResponsesInHistory', () {
    test('equal instances match; differing value does not', () {
      const a = UpdateSaveLargeResponsesInHistory(value: true);
      const b = UpdateSaveLargeResponsesInHistory(value: true);
      const c = UpdateSaveLargeResponsesInHistory(value: false);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.value, isTrue);
      expect(a.props, [true]);
    });
  });

  group('UpdateSplitRatio', () {
    test('equal instances match; differing ratio does not', () {
      const a = UpdateSplitRatio(0.5);
      const b = UpdateSplitRatio(0.5);
      const c = UpdateSplitRatio(0.25);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.ratio, 0.5);
      expect(a.props, [0.5]);
    });
  });

  group('UpdateSideMenuWidth', () {
    test('equal instances match; differing width does not', () {
      const a = UpdateSideMenuWidth(280);
      const b = UpdateSideMenuWidth(280);
      const c = UpdateSideMenuWidth(320);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.width, 280);
      expect(a.props, [280.0]);
    });
  });

  group('UpdateThemeId', () {
    test('equal instances match; differing themeId does not', () {
      const a = UpdateThemeId('brutalist');
      const b = UpdateThemeId('brutalist');
      const c = UpdateThemeId('dracula');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.themeId, 'brutalist');
      expect(a.props, ['brutalist']);
    });
  });

  group('UpdateActiveEnvironmentId', () {
    test('equal instances match; differing id does not', () {
      const a = UpdateActiveEnvironmentId('env-1');
      const b = UpdateActiveEnvironmentId('env-1');
      const c = UpdateActiveEnvironmentId('env-2');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.id, 'env-1');
      expect(a.props, ['env-1']);
    });

    test('null id (deactivate) equals null id, differs from a set id', () {
      const cleared = UpdateActiveEnvironmentId(null);
      expect(cleared, equals(const UpdateActiveEnvironmentId(null)));
      expect(cleared, isNot(equals(const UpdateActiveEnvironmentId('env-1'))));
      expect(cleared.id, isNull);
      expect(cleared.props, [null]);
    });
  });

  group('UpdateConnectTimeout', () {
    test('equal instances match; differing ms does not', () {
      const a = UpdateConnectTimeout(3000);
      const b = UpdateConnectTimeout(3000);
      const c = UpdateConnectTimeout(1000);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.ms, 3000);
      expect(a.props, [3000]);
    });
  });

  group('UpdateSendTimeout', () {
    test('equal instances match; differing ms does not', () {
      const a = UpdateSendTimeout(3000);
      const b = UpdateSendTimeout(3000);
      const c = UpdateSendTimeout(0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.ms, 3000);
      expect(a.props, [3000]);
    });
  });

  group('UpdateReceiveTimeout', () {
    test('equal instances match; differing ms does not', () {
      const a = UpdateReceiveTimeout(5000);
      const b = UpdateReceiveTimeout(5000);
      const c = UpdateReceiveTimeout(9000);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.ms, 5000);
      expect(a.props, [5000]);
    });
  });

  group('timeout events', () {
    test('different event types with identical ms are not equal', () {
      // Equatable includes runtimeType — a connect timeout must never be
      // mistaken for a send/receive timeout carrying the same value.
      const connect = UpdateConnectTimeout(1000);
      const send = UpdateSendTimeout(1000);
      const receive = UpdateReceiveTimeout(1000);
      expect(connect, isNot(equals(send)));
      expect(send, isNot(equals(receive)));
      expect(connect, isNot(equals(receive)));
    });
  });

  group('UpdateFollowRedirects', () {
    test('equal instances match; differing value does not', () {
      const a = UpdateFollowRedirects(value: false);
      const b = UpdateFollowRedirects(value: false);
      const c = UpdateFollowRedirects(value: true);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.value, isFalse);
      expect(a.props, [false]);
    });
  });

  group('UpdateMaxRedirects', () {
    test('equal instances match; differing value does not', () {
      const a = UpdateMaxRedirects(5);
      const b = UpdateMaxRedirects(5);
      const c = UpdateMaxRedirects(1);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.value, 5);
      expect(a.props, [5]);
    });
  });

  group('UpdateVerifySsl', () {
    test('equal instances match; differing value does not', () {
      const a = UpdateVerifySsl(value: false);
      const b = UpdateVerifySsl(value: false);
      const c = UpdateVerifySsl(value: true);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.value, isFalse);
      expect(a.props, [false]);
    });
  });

  group('UpdateClientCertificate', () {
    test('equal trios match', () {
      const a = UpdateClientCertificate(
        certPath: '/certs/client.pem',
        keyPath: '/certs/client.key',
        passphrase: 'secret',
      );
      const b = UpdateClientCertificate(
        certPath: '/certs/client.pem',
        keyPath: '/certs/client.key',
        passphrase: 'secret',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.certPath, '/certs/client.pem');
      expect(a.keyPath, '/certs/client.key');
      expect(a.passphrase, 'secret');
      expect(a.props, ['/certs/client.pem', '/certs/client.key', 'secret']);
    });

    test('each differing field breaks equality', () {
      const base = UpdateClientCertificate(
        certPath: '/c.pem',
        keyPath: '/k.pem',
        passphrase: 'p',
      );
      expect(
        base,
        isNot(
          equals(
            const UpdateClientCertificate(
              certPath: '/other.pem',
              keyPath: '/k.pem',
              passphrase: 'p',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const UpdateClientCertificate(
              certPath: '/c.pem',
              keyPath: '/other.pem',
              passphrase: 'p',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const UpdateClientCertificate(
              certPath: '/c.pem',
              keyPath: '/k.pem',
            ),
          ),
        ),
      );
    });

    test('all-null disconnect event equals itself', () {
      const disconnect = UpdateClientCertificate();
      expect(disconnect, equals(const UpdateClientCertificate()));
      expect(disconnect.certPath, isNull);
      expect(disconnect.keyPath, isNull);
      expect(disconnect.passphrase, isNull);
      expect(disconnect.props, [null, null, null]);
    });
  });

  group('UpdateProxyUrl', () {
    test('equal instances match; differing url does not; null clears', () {
      const a = UpdateProxyUrl('127.0.0.1:8888');
      const b = UpdateProxyUrl('127.0.0.1:8888');
      const c = UpdateProxyUrl('10.0.0.1:3128');
      const cleared = UpdateProxyUrl(null);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(cleared)));
      expect(cleared, equals(const UpdateProxyUrl(null)));
      expect(a.url, '127.0.0.1:8888');
      expect(cleared.url, isNull);
      expect(a.props, ['127.0.0.1:8888']);
    });
  });

  group('UpdateWorkspacePath', () {
    test('equal path+bookmark pairs match', () {
      const a = UpdateWorkspacePath('/ws', bookmark: 'Ym9vaw==');
      const b = UpdateWorkspacePath('/ws', bookmark: 'Ym9vaw==');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.path, '/ws');
      expect(a.bookmark, 'Ym9vaw==');
      expect(a.props, ['/ws', 'Ym9vaw==']);
    });

    test('differing path or bookmark breaks equality', () {
      const base = UpdateWorkspacePath('/ws', bookmark: 'Ym9vaw==');
      expect(
        base,
        isNot(
          equals(const UpdateWorkspacePath('/other', bookmark: 'Ym9vaw==')),
        ),
      );
      expect(base, isNot(equals(const UpdateWorkspacePath('/ws'))));
    });

    test('double-null disconnect event equals itself', () {
      const disconnect = UpdateWorkspacePath(null);
      expect(disconnect, equals(const UpdateWorkspacePath(null)));
      expect(disconnect.path, isNull);
      expect(disconnect.bookmark, isNull);
      expect(disconnect.props, [null, null]);
    });
  });

  group('UpdateCheckForUpdatesOnStartup', () {
    test('equal instances match; differing enabled does not', () {
      const a = UpdateCheckForUpdatesOnStartup(enabled: true);
      const b = UpdateCheckForUpdatesOnStartup(enabled: true);
      const c = UpdateCheckForUpdatesOnStartup(enabled: false);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.enabled, isTrue);
      expect(a.props, [true]);
    });
  });

  group('SetSkippedUpdateVersion', () {
    test('equal instances match; differing version does not; null clears', () {
      const a = SetSkippedUpdateVersion('1.9.0');
      const b = SetSkippedUpdateVersion('1.9.0');
      const c = SetSkippedUpdateVersion('2.0.0');
      const cleared = SetSkippedUpdateVersion(null);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(cleared)));
      expect(a.version, '1.9.0');
      expect(cleared.version, isNull);
      expect(a.props, ['1.9.0']);
    });
  });

  group('UpdateGitIdentity', () {
    test('equal name+email pairs match', () {
      const a = UpdateGitIdentity(name: 'Ada', email: 'ada@example.com');
      const b = UpdateGitIdentity(name: 'Ada', email: 'ada@example.com');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.name, 'Ada');
      expect(a.email, 'ada@example.com');
      expect(a.props, ['Ada', 'ada@example.com']);
    });

    test('differing name or email breaks equality; nulls clear fields', () {
      const base = UpdateGitIdentity(name: 'Ada', email: 'ada@example.com');
      expect(
        base,
        isNot(
          equals(
            const UpdateGitIdentity(name: 'Bob', email: 'ada@example.com'),
          ),
        ),
      );
      expect(base, isNot(equals(const UpdateGitIdentity(name: 'Ada'))));
      const cleared = UpdateGitIdentity();
      expect(cleared, equals(const UpdateGitIdentity()));
      expect(cleared.name, isNull);
      expect(cleared.email, isNull);
      expect(cleared.props, [null, null]);
    });
  });
}

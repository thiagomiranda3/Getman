// test/core/utils/workspace/workspace_bookmark_test.dart
//
// WorkspaceBookmarks behavior: the macOS-only platform gate, method-channel
// result mapping for pickDirectory/resolveAndAccess, bookmark-refresh
// fallbacks, and the safe-null error paths.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/workspace/workspace_bookmark.dart';

const _channel = MethodChannel('getman/workspace_bookmark');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
  }

  group('value types', () {
    test('WorkspaceLocation carries path and an optional bookmark', () {
      const bare = WorkspaceLocation('/ws');
      expect(bare.path, '/ws');
      expect(bare.bookmark, isNull);
      const full = WorkspaceLocation('/ws', bookmark: 'b64');
      expect(full.bookmark, 'b64');
    });

    test('WorkspaceAccessResult carries path/bookmark/stale', () {
      const result = WorkspaceAccessResult(
        path: '/ws',
        bookmark: 'b64',
        stale: true,
      );
      expect(result.path, '/ws');
      expect(result.bookmark, 'b64');
      expect(result.stale, isTrue);
    });
  });

  group('off macOS (tests default to android)', () {
    test('supported is false and both methods no-op to null', () async {
      mockChannel((call) async => fail('channel must not be touched'));
      expect(WorkspaceBookmarks.supported, isFalse);
      expect(await WorkspaceBookmarks.pickDirectory(), isNull);
      expect(await WorkspaceBookmarks.resolveAndAccess('b64'), isNull);
    });
  });

  group('on macOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    test('supported is true', () {
      expect(WorkspaceBookmarks.supported, isTrue);
    });

    group('pickDirectory', () {
      test('maps the native path + bookmark', () async {
        mockChannel((call) async {
          expect(call.method, 'pickDirectory');
          return {'path': '/Users/me/ws', 'bookmark': 'fresh-b64'};
        });
        final location = await WorkspaceBookmarks.pickDirectory();
        expect(location?.path, '/Users/me/ws');
        expect(location?.bookmark, 'fresh-b64');
      });

      test('returns null on cancel (native null)', () async {
        mockChannel((call) async => null);
        expect(await WorkspaceBookmarks.pickDirectory(), isNull);
      });

      test('returns null when the native result has no path', () async {
        mockChannel((call) async => {'bookmark': 'b64'});
        expect(await WorkspaceBookmarks.pickDirectory(), isNull);
      });

      test('returns null when the channel throws', () async {
        mockChannel(
          (call) async => throw PlatformException(code: 'denied'),
        );
        expect(await WorkspaceBookmarks.pickDirectory(), isNull);
      });
    });

    group('resolveAndAccess', () {
      test('maps path, refreshed bookmark and staleness', () async {
        mockChannel((call) async {
          expect(call.method, 'resolveBookmark');
          expect(call.arguments, {'bookmark': 'stored-b64'});
          return {'path': '/ws', 'bookmark': 'refreshed-b64', 'stale': true};
        });
        final result = await WorkspaceBookmarks.resolveAndAccess('stored-b64');
        expect(result?.path, '/ws');
        expect(result?.bookmark, 'refreshed-b64');
        expect(result?.stale, isTrue);
      });

      test(
        'falls back to the original bookmark and stale=false when the '
        'native side omits them',
        () async {
          mockChannel((call) async => {'path': '/ws'});
          final result = await WorkspaceBookmarks.resolveAndAccess(
            'stored-b64',
          );
          expect(result?.bookmark, 'stored-b64');
          expect(result?.stale, isFalse);
        },
      );

      test('returns null when access could not be re-acquired', () async {
        mockChannel((call) async => null);
        expect(await WorkspaceBookmarks.resolveAndAccess('b64'), isNull);
      });

      test('returns null when the native result has no path', () async {
        mockChannel((call) async => {'stale': false});
        expect(await WorkspaceBookmarks.resolveAndAccess('b64'), isNull);
      });

      test('returns null when the channel throws', () async {
        mockChannel(
          (call) async => throw PlatformException(code: 'resolve-failed'),
        );
        expect(await WorkspaceBookmarks.resolveAndAccess('b64'), isNull);
      });
    });
  });
}

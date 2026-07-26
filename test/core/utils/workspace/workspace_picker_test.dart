// test/core/utils/workspace/workspace_picker_test.dart
//
// pickWorkspaceDirectory routing: the macOS security-scoped-bookmark path
// vs. the plain file_picker directory dialog elsewhere, plus cancel and
// error fallbacks. (The kIsWeb early-return is untestable on the VM.)
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/workspace/workspace_picker.dart';

const _bookmarkChannel = MethodChannel('getman/workspace_bookmark');
const _pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_bookmarkChannel, null)
      ..setMockMethodCallHandler(_pickerChannel, null);
  });

  void mockChannel(
    MethodChannel channel,
    Future<Object?> Function(MethodCall call) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  group('non-macOS platforms (tests default to android)', () {
    test('returns the file_picker directory with no bookmark', () async {
      var nativePickerTouched = false;
      mockChannel(_bookmarkChannel, (call) async {
        nativePickerTouched = true;
        return null;
      });
      mockChannel(_pickerChannel, (call) async {
        expect(call.method, 'dir');
        return '/work/dir';
      });
      final location = await pickWorkspaceDirectory();
      expect(location?.path, '/work/dir');
      expect(location?.bookmark, isNull);
      expect(nativePickerTouched, isFalse);
    });

    test('returns null on cancel', () async {
      mockChannel(_pickerChannel, (call) async => null);
      expect(await pickWorkspaceDirectory(), isNull);
    });

    test('returns null when the picker throws a PlatformException', () async {
      mockChannel(
        _pickerChannel,
        (call) async => throw PlatformException(code: 'denied'),
      );
      expect(await pickWorkspaceDirectory(), isNull);
    });

    test('returns null when the picker throws an unexpected error', () async {
      // A non-String payload makes FilePicker.getDirectoryPath's
      // invokeMethod<String> throw a TypeError, which file_picker's own
      // `on PlatformException` filter does NOT swallow — exercising
      // pickWorkspaceDirectory's catch-all fallback.
      mockChannel(_pickerChannel, (call) async => 42);
      expect(await pickWorkspaceDirectory(), isNull);
    });
  });

  group('macOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    test('uses the native bookmark picker, not file_picker', () async {
      var filePickerTouched = false;
      mockChannel(_pickerChannel, (call) async {
        filePickerTouched = true;
        return null;
      });
      mockChannel(
        _bookmarkChannel,
        (call) async => {'path': '/mac/ws', 'bookmark': 'b64'},
      );
      final location = await pickWorkspaceDirectory();
      expect(location?.path, '/mac/ws');
      expect(location?.bookmark, 'b64');
      expect(filePickerTouched, isFalse);
    });

    test('propagates a native cancel as null', () async {
      mockChannel(_bookmarkChannel, (call) async => null);
      expect(await pickWorkspaceDirectory(), isNull);
    });
  });
}

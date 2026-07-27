// test/core/utils/json_file_io_file_ops_test.dart
//
// File-touching behavior of json_file_io: readPickedFile source preference,
// the save-with-feedback flows (write + snackbar, cancel, error) and the
// multi-file import flow, driving file_picker through its mocked method
// channel and real temp files.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/json_file_io.dart';

const _pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('json_file_io_test');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, null);
    tempDir.deleteSync(recursive: true);
  });

  void mockPicker(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, handler);
  }

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    return tester.element(find.byType(SizedBox));
  }

  group('readPickedFile', () {
    test('prefers in-memory bytes over the path', () async {
      final onDisk = File('${tempDir.path}/a.json')
        ..writeAsStringSync('{"from":"disk"}');
      final picked = PlatformFile(
        name: 'a.json',
        size: 16,
        path: onDisk.path,
        bytes: Uint8List.fromList(utf8.encode('{"from":"memory"}')),
      );
      expect(await readPickedFile(picked), '{"from":"memory"}');
    });

    test('falls back to reading the path when bytes are absent', () async {
      final onDisk = File('${tempDir.path}/b.json')
        ..writeAsStringSync('{"b":2}');
      final picked = PlatformFile(name: 'b.json', size: 7, path: onDisk.path);
      expect(await readPickedFile(picked), '{"b":2}');
    });

    test('returns null when the file has neither bytes nor path', () async {
      final picked = PlatformFile(name: 'ghost.json', size: 0);
      expect(await readPickedFile(picked), isNull);
    });
  });

  group('saveTextFileWithFeedback', () {
    testWidgets('writes the picked path and reports it in a snackbar', (
      tester,
    ) async {
      final target = '${tempDir.path}/exported.json';
      MethodCall? saveCall;
      mockPicker((call) async {
        saveCall = call;
        return target;
      });
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => saveTextFileWithFeedback(
          context,
          content: '{"a":1}',
          fileName: 'exported.json',
          dialogTitle: 'Export',
        ),
      );
      await tester.pump();

      expect(File(target).readAsStringSync(), '{"a":1}');
      expect(find.text('Exported to $target'), findsOneWidget);
      expect(saveCall?.method, 'save');
      final args = saveCall?.arguments as Map<Object?, Object?>?;
      expect(args?['fileName'], 'exported.json');
      expect(args?['allowedExtensions'], ['json']);
    });

    testWidgets('a cancelled picker writes nothing and stays silent', (
      tester,
    ) async {
      mockPicker((call) async => null);
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => saveTextFileWithFeedback(
          context,
          content: 'x',
          fileName: 'out.json',
          dialogTitle: 'Export',
        ),
      );
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      expect(tempDir.listSync(), isEmpty);
    });

    testWidgets('a picker failure surfaces an Export failed snackbar', (
      tester,
    ) async {
      mockPicker(
        (call) async => throw PlatformException(code: 'fail', message: 'boom'),
      );
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => saveTextFileWithFeedback(
          context,
          content: 'x',
          fileName: 'out.json',
          dialogTitle: 'Export',
        ),
      );
      await tester.pump();

      expect(find.textContaining('Export failed:'), findsOneWidget);
    });

    testWidgets('custom allowedExtensions reach the picker', (tester) async {
      MethodCall? saveCall;
      mockPicker((call) async {
        saveCall = call;
        return null; // cancel — only the arguments matter here
      });
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => saveTextFileWithFeedback(
          context,
          content: 'body',
          fileName: 'response.txt',
          dialogTitle: 'Save body',
          allowedExtensions: const ['json', 'txt'],
        ),
      );
      final args = saveCall?.arguments as Map<Object?, Object?>?;
      expect(args?['allowedExtensions'], ['json', 'txt']);
    });
  });

  group('saveJsonFileWithFeedback', () {
    testWidgets('delegates to the text save (writes + snackbar)', (
      tester,
    ) async {
      final target = '${tempDir.path}/col.json';
      mockPicker((call) async => target);
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => saveJsonFileWithFeedback(
          context,
          jsonString: '{"col":true}',
          fileName: 'col.json',
          dialogTitle: 'Export collection',
        ),
      );
      await tester.pump();

      expect(File(target).readAsStringSync(), '{"col":true}');
      expect(find.text('Exported to $target'), findsOneWidget);
    });
  });

  group('saveBytesFileWithFeedback', () {
    testWidgets('writes raw bytes and reports Saved to', (tester) async {
      final target = '${tempDir.path}/img.bin';
      final bytes = Uint8List.fromList([1, 2, 3, 255]);
      mockPicker((call) async => target);
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => saveBytesFileWithFeedback(
          context,
          bytes: bytes,
          fileName: 'img.bin',
          dialogTitle: 'Save bytes',
        ),
      );
      await tester.pump();

      expect(File(target).readAsBytesSync(), bytes);
      expect(find.text('Saved to $target'), findsOneWidget);
    });

    testWidgets('a picker failure surfaces a Save failed snackbar', (
      tester,
    ) async {
      mockPicker(
        (call) async => throw PlatformException(code: 'fail', message: 'boom'),
      );
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => saveBytesFileWithFeedback(
          context,
          bytes: Uint8List.fromList([1]),
          fileName: 'img.bin',
          dialogTitle: 'Save bytes',
        ),
      );
      await tester.pump();

      expect(find.textContaining('Save failed:'), findsOneWidget);
    });
  });

  group('importJsonFilesWithFeedback', () {
    List<String> parseJsonList(String content) => [
      for (final v in jsonDecode(content) as List<dynamic>) v.toString(),
    ];

    Map<String, Object?> pickedFileMap({
      required String name,
      String? path,
      Uint8List? bytes,
    }) => {'name': name, 'path': path, 'bytes': bytes, 'size': 0};

    testWidgets('parses every picked file and reports the imported count', (
      tester,
    ) async {
      final onDisk = File('${tempDir.path}/disk.json')
        ..writeAsStringSync('["z"]');
      mockPicker(
        (call) async => [
          pickedFileMap(
            name: 'mem.json',
            bytes: Uint8List.fromList(utf8.encode('["x","y"]')),
          ),
          pickedFileMap(name: 'disk.json', path: onDisk.path),
        ],
      );
      final context = await pumpHost(tester);
      final imported = <String>[];
      await tester.runAsync(
        () => importJsonFilesWithFeedback<String>(
          context,
          parse: parseJsonList,
          onImported: imported.addAll,
          noun: 'thing',
        ),
      );
      await tester.pump();

      expect(imported, ['x', 'y', 'z']);
      expect(find.text('Imported 3 thing(s).'), findsOneWidget);
    });

    testWidgets(
      'keeps good files and reports unreadable/unparsable ones as skipped',
      (tester) async {
        mockPicker(
          (call) async => [
            pickedFileMap(
              name: 'good.json',
              bytes: Uint8List.fromList(utf8.encode('["ok"]')),
            ),
            pickedFileMap(
              name: 'broken.json',
              bytes: Uint8List.fromList(utf8.encode('not json')),
            ),
            pickedFileMap(name: 'ghost.json'),
          ],
        );
        final context = await pumpHost(tester);
        final imported = <String>[];
        await tester.runAsync(
          () => importJsonFilesWithFeedback<String>(
            context,
            parse: parseJsonList,
            onImported: imported.addAll,
            noun: 'environment',
          ),
        );
        await tester.pump();

        expect(imported, ['ok']);
        final snackText = tester
            .widget<Text>(
              find.descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Text),
              ),
            )
            .data;
        expect(snackText, startsWith('Imported 1 environment(s). Skipped:'));
        expect(snackText, contains('broken.json'));
        expect(snackText, contains('ghost.json: unable to read file'));
      },
    );

    testWidgets('reports Import failed when every file fails to parse', (
      tester,
    ) async {
      mockPicker(
        (call) async => [
          pickedFileMap(
            name: 'broken.json',
            bytes: Uint8List.fromList(utf8.encode('nope')),
          ),
        ],
      );
      final context = await pumpHost(tester);
      var onImportedCalled = false;
      await tester.runAsync(
        () => importJsonFilesWithFeedback<String>(
          context,
          parse: parseJsonList,
          onImported: (_) => onImportedCalled = true,
          noun: 'collection',
        ),
      );
      await tester.pump();

      expect(onImportedCalled, isFalse);
      expect(find.textContaining('Import failed: broken.json'), findsOneWidget);
    });

    testWidgets('a cancelled picker imports nothing and stays silent', (
      tester,
    ) async {
      mockPicker((call) async => null);
      final context = await pumpHost(tester);
      var onImportedCalled = false;
      await tester.runAsync(
        () => importJsonFilesWithFeedback<String>(
          context,
          parse: parseJsonList,
          onImported: (_) => onImportedCalled = true,
          noun: 'collection',
        ),
      );
      await tester.pump();

      expect(onImportedCalled, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a picker failure surfaces an Import failed snackbar', (
      tester,
    ) async {
      mockPicker(
        (call) async => throw PlatformException(code: 'fail', message: 'boom'),
      );
      final context = await pumpHost(tester);
      await tester.runAsync(
        () => importJsonFilesWithFeedback<String>(
          context,
          parse: parseJsonList,
          onImported: (_) {},
          noun: 'collection',
        ),
      );
      await tester.pump();

      expect(find.textContaining('Import failed:'), findsOneWidget);
    });
  });
}

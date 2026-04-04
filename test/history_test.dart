import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:getman/providers/history_provider.dart';
import 'package:getman/providers/settings_provider.dart';
import 'package:getman/models/request_config.dart';
import 'package:getman/services/storage_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';

class MockPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.';
  @override
  Future<String?> getTemporaryPath() async => '.';
}

void main() {
  test('HistoryNotifier respects history limit', () async {
    // Setup Mock Hive
    PathProviderPlatform.instance = MockPathProvider();
    final tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);
    await StorageService.init();

    final container = ProviderContainer();
    final historyNotifier = container.read(historyProvider.notifier);
    final settingsNotifier = container.read(settingsProvider.notifier);

    // Set limit to 2
    settingsNotifier.updateHistoryLimit(2);

    // Add 3 requests
    historyNotifier.addRequest(HttpRequestConfig(url: '1'));
    historyNotifier.addRequest(HttpRequestConfig(url: '2'));
    historyNotifier.addRequest(HttpRequestConfig(url: '3'));

    final history = container.read(historyProvider);
    expect(history.length, 2);
    expect(history[0].url, '3');
    expect(history[1].url, '2');

    tempDir.deleteSync(recursive: true);
  });
}

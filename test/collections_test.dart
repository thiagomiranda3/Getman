import 'package:flutter_test/flutter_test.dart';
import 'package:getman/providers/collections_provider.dart';
import 'package:getman/services/storage_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MockPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.';
  @override
  Future<String?> getTemporaryPath() async => '.';
}

void main() {
  test('CollectionsNotifier sorts favorites first and then alphabetically', () async {
    PathProviderPlatform.instance = MockPathProvider();
    final tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);
    await StorageService.init();

    final container = ProviderContainer();
    final notifier = container.read(collectionsProvider.notifier);

    // Add folders in unsorted order
    notifier.addFolder('B');
    notifier.addFolder('A');
    notifier.addFolder('C');

    var state = container.read(collectionsProvider);
    expect(state[0].name, 'A');
    expect(state[1].name, 'B');
    expect(state[2].name, 'C');

    // Favorite 'C'
    notifier.toggleFavorite(state[2].id);
    
    state = container.read(collectionsProvider);
    expect(state[0].name, 'C'); // Favorite first
    expect(state[0].isFavorite, true);
    expect(state[1].name, 'A');
    expect(state[2].name, 'B');

    // Recursive sort test
    notifier.addFolder('subB', parentId: state[1].id); // folder A
    notifier.addFolder('subA', parentId: state[1].id); // folder A
    
    state = container.read(collectionsProvider);
    expect(state[1].children[0].name, 'subA');
    expect(state[1].children[1].name, 'subB');

    tempDir.deleteSync(recursive: true);
  });
}

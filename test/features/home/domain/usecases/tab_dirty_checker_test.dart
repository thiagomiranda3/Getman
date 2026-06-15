import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

void main() {
  const checker = TabDirtyChecker();

  HttpRequestTabEntity tab(HttpRequestConfigEntity config, {String? nodeId}) =>
      HttpRequestTabEntity(
        tabId: 't',
        config: config,
        collectionNodeId: nodeId,
      );

  group('unlinked tab', () {
    test('a pristine default config is not dirty', () {
      final t = tab(const HttpRequestConfigEntity(id: 't'));
      expect(checker(tab: t, savedConfigs: const {}), isFalse);
    });

    test('a modified config is dirty', () {
      final t = tab(
        const HttpRequestConfigEntity(id: 't', url: 'https://x.dev'),
      );
      expect(checker(tab: t, savedConfigs: const {}), isTrue);
    });
  });

  group('linked tab', () {
    const saved = HttpRequestConfigEntity(id: 't', url: 'https://saved.dev');

    test('matching the saved config is not dirty', () {
      final t = tab(saved, nodeId: 'n1');
      expect(checker(tab: t, savedConfigs: {'n1': saved}), isFalse);
    });

    test('differing from the saved config is dirty', () {
      final t = tab(
        const HttpRequestConfigEntity(id: 't', url: 'https://edited.dev'),
        nodeId: 'n1',
      );
      expect(checker(tab: t, savedConfigs: {'n1': saved}), isTrue);
    });

    test('a node missing from the index is dirty', () {
      final t = tab(saved, nodeId: 'gone');
      expect(checker(tab: t, savedConfigs: {'n1': saved}), isTrue);
    });
  });
}

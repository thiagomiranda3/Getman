import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';

void main() {
  group('HttpRequestConfig.toEntity() legacy-params migration', () {
    test('merges legacy params map into URL when non-empty', () {
      final model = HttpRequestConfig(
        id: 'id',
        method: 'GET',
        url: 'https://x.y/path',
        params: {'a': '1', 'b': '2'},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?a=1&b=2');
      expect(entity.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });

    test('replaces existing URL query with legacy params when both present', () {
      // Pre-migration data shouldn't have both, but be lenient: legacy map
      // wins to restore user intent (they had explicit params rows before).
      final model = HttpRequestConfig(
        id: 'id',
        url: 'https://x.y/path?stale=1',
        params: {'fresh': '2'},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?fresh=2');
    });

    test('passes URL through when legacy params is empty', () {
      final model = HttpRequestConfig(
        id: 'id',
        url: 'https://x.y/path?already=here',
        params: const {},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?already=here');
    });

    test('fromEntity writes an empty legacy params map', () {
      const entity = HttpRequestConfigEntity(
        id: 'id',
        url: 'https://x.y/path?a=1',
      );
      final model = HttpRequestConfig.fromEntity(entity);
      expect(model.params, isEmpty);
      expect(model.url, 'https://x.y/path?a=1');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';

void main() {
  group('HttpRequestConfig', () {
    test('round-trips through entity', () {
      const entity = HttpRequestConfigEntity(
        id: '1',
        url: 'https://example.com',
        method: 'GET',
      );

      final model = HttpRequestConfig.fromEntity(entity);
      expect(model.id, entity.id);
      expect(model.url, entity.url);

      final back = model.toEntity();
      expect(back, entity);
    });

    test('compares equal when all non-id fields match', () {
      final a = HttpRequestConfig(id: '1', method: 'GET', url: 'url');
      final b = HttpRequestConfig(id: '1', method: 'GET', url: 'url');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    // DO NOT CHANGE — history dedup depends on `==` ignoring `id`.
    // Without this contract, identical requests with different generated
    // UUIDs would be treated as distinct and the history box would grow
    // unbounded. See CLAUDE.md §6.
    test('equality and hashCode ignore id (dedup contract)', () {
      final a = HttpRequestConfig(id: 'id-a', method: 'POST', url: 'https://api', body: '{"x":1}');
      final b = HttpRequestConfig(id: 'id-b', method: 'POST', url: 'https://api', body: '{"x":1}');
      expect(a == b, isTrue, reason: 'Equality must ignore id');
      expect(a.hashCode, b.hashCode, reason: 'hashCode must also ignore id');
    });

    test('equality distinguishes different methods', () {
      final a = HttpRequestConfig(id: '1', method: 'GET', url: 'url');
      final b = HttpRequestConfig(id: '1', method: 'POST', url: 'url');
      expect(a == b, isFalse);
    });

    test('equality distinguishes different bodies', () {
      final a = HttpRequestConfig(id: '1', method: 'POST', url: 'url', body: 'one');
      final b = HttpRequestConfig(id: '1', method: 'POST', url: 'url', body: 'two');
      expect(a == b, isFalse);
    });
  });
}

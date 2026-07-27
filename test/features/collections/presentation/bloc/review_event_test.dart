// Equality/props tests for every ReviewEvent class: identical instances are
// equal, and each declared field participates in equality (a difference in
// any single field makes the events unequal) — guarding against a field
// silently dropping out of props.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';

void main() {
  group('LoadReview', () {
    test('root participates in equality', () {
      expect(const LoadReview('/ws'), const LoadReview('/ws'));
      expect(const LoadReview('/ws'), isNot(const LoadReview('/other')));
    });
  });

  group('StageNode', () {
    test('every field participates in equality', () {
      expect(
        const StageNode('/ws', 'a.json'),
        const StageNode('/ws', 'a.json'),
      );
      expect(
        const StageNode('/ws', 'a.json'),
        isNot(const StageNode('/other', 'a.json')),
      );
      expect(
        const StageNode('/ws', 'a.json'),
        isNot(const StageNode('/ws', 'b.json')),
      );
    });
  });

  group('UnstageNode', () {
    test('every field participates in equality', () {
      expect(
        const UnstageNode('/ws', 'a.json'),
        const UnstageNode('/ws', 'a.json'),
      );
      expect(
        const UnstageNode('/ws', 'a.json'),
        isNot(const UnstageNode('/other', 'a.json')),
      );
      expect(
        const UnstageNode('/ws', 'a.json'),
        isNot(const UnstageNode('/ws', 'b.json')),
      );
    });

    test('is a distinct event type from StageNode', () {
      expect(
        const UnstageNode('/ws', 'a.json'),
        isNot(const StageNode('/ws', 'a.json')),
      );
    });
  });

  group('StageAll', () {
    test('root participates in equality', () {
      expect(const StageAll('/ws'), const StageAll('/ws'));
      expect(const StageAll('/ws'), isNot(const StageAll('/other')));
    });
  });

  group('UnstageAll', () {
    test('root participates in equality', () {
      expect(const UnstageAll('/ws'), const UnstageAll('/ws'));
      expect(const UnstageAll('/ws'), isNot(const UnstageAll('/other')));
    });

    test('is a distinct event type from StageAll', () {
      expect(const UnstageAll('/ws'), isNot(const StageAll('/ws')));
    });
  });

  group('SelectEntry', () {
    test('path participates in equality', () {
      expect(const SelectEntry('a.json'), const SelectEntry('a.json'));
      expect(const SelectEntry('a.json'), isNot(const SelectEntry('b.json')));
    });
  });

  group('Commit', () {
    test('equal for identical fields', () {
      expect(
        const Commit('/ws', 'msg', authorName: 'Me', authorEmail: 'me@x.dev'),
        const Commit('/ws', 'msg', authorName: 'Me', authorEmail: 'me@x.dev'),
      );
    });

    test('every field participates in equality', () {
      const base = Commit(
        '/ws',
        'msg',
        authorName: 'Me',
        authorEmail: 'me@x.dev',
      );
      expect(
        base,
        isNot(
          const Commit(
            '/other',
            'msg',
            authorName: 'Me',
            authorEmail: 'me@x.dev',
          ),
        ),
      );
      expect(
        base,
        isNot(
          const Commit(
            '/ws',
            'other',
            authorName: 'Me',
            authorEmail: 'me@x.dev',
          ),
        ),
      );
      expect(
        base,
        isNot(const Commit('/ws', 'msg', authorEmail: 'me@x.dev')),
      );
      expect(
        base,
        isNot(const Commit('/ws', 'msg', authorName: 'Me')),
      );
    });
  });

  group('InitRepo', () {
    test('root participates in equality', () {
      expect(const InitRepo('/ws'), const InitRepo('/ws'));
      expect(const InitRepo('/ws'), isNot(const InitRepo('/other')));
    });
  });
}

// Unit tests for groupHistoryByDay (D3): TODAY/YESTERDAY around midnight
// boundaries, weekday-month-day labels, newest-day-first ordering, and the
// trailing EARLIER bucket for legacy entries without sentAt.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/logic/history_day_grouper.dart';

HttpRequestConfigEntity _entry(String id, {DateTime? sentAt}) =>
    HttpRequestConfigEntity(id: id, url: 'https://x.dev/$id', sentAt: sentAt);

void main() {
  // Friday 2026-07-24, one minute after midnight — the boundary-sensitive
  // moment: "two minutes ago" is a different calendar day.
  final now = DateTime(2026, 7, 24, 0, 1);

  test('an entry sent 90 seconds ago but before midnight is YESTERDAY', () {
    final groups = groupHistoryByDay(
      [
        _entry('a', sentAt: DateTime(2026, 7, 24, 0, 0, 30)),
        _entry('b', sentAt: DateTime(2026, 7, 23, 23, 59)),
      ],
      now,
    );
    expect(groups.map((g) => g.label), ['TODAY', 'YESTERDAY']);
    expect(groups.first.entries.single.id, 'a');
    expect(groups.last.entries.single.id, 'b');
  });

  test('older days get weekday-month-day labels (MON, JUL 20 style)', () {
    final groups = groupHistoryByDay(
      [_entry('a', sentAt: DateTime(2026, 7, 20, 15))],
      now,
    );
    expect(groups.single.label, 'MON, JUL 20');
  });

  test('groups are newest-day-first and keep entry order within a day', () {
    final groups = groupHistoryByDay(
      [
        _entry('new1', sentAt: DateTime(2026, 7, 24, 0, 0, 45)),
        _entry('new2', sentAt: DateTime(2026, 7, 24, 0, 0, 30)),
        _entry('old', sentAt: DateTime(2026, 7, 22, 9)),
      ],
      now,
    );
    expect(groups, hasLength(2));
    expect(groups.first.label, 'TODAY');
    expect(groups.first.entries.map((e) => e.id), ['new1', 'new2']);
    expect(groups.last.label, 'WED, JUL 22');
  });

  test(
    'legacy entries without sentAt collect into a trailing EARLIER group',
    () {
      final groups = groupHistoryByDay(
        [
          _entry('dated', sentAt: DateTime(2026, 7, 24, 0, 0, 45)),
          _entry('legacy'),
        ],
        now,
      );
      expect(groups, hasLength(2));
      expect(groups.last.label, kEarlierGroupLabel);
      expect(groups.last.entries.single.id, 'legacy');
    },
  );

  test('YESTERDAY works across a month boundary', () {
    final firstOfMonth = DateTime(2026, 8, 1, 8);
    final groups = groupHistoryByDay(
      [_entry('a', sentAt: DateTime(2026, 7, 31, 22))],
      firstOfMonth,
    );
    expect(groups.single.label, 'YESTERDAY');
  });

  test('empty input produces no groups', () {
    expect(groupHistoryByDay(const [], now), isEmpty);
  });
}

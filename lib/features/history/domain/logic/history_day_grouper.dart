// Pure day-grouping for the HISTORY tab (D3): splits a newest-first history
// list into ordered calendar-day groups with UI-ready labels — 'TODAY',
// 'YESTERDAY', then 'MON, JUL 20'-style weekday-month-day; entries without
// a sentAt timestamp (records persisted before the field existed) collect
// into a trailing 'EARLIER' group. Pure Dart on purpose: unit-tested around
// midnight/month boundaries without widget or wall-clock plumbing (the
// caller supplies `now`). No intl dependency — labels use fixed all-caps
// English abbreviations matching the app's label style.

import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';

const List<String> _weekdays = [
  'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN', //
];
const List<String> _months = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// Label of the trailing group for legacy entries with a null `sentAt`.
const String kEarlierGroupLabel = 'EARLIER';

/// One rendered section of the HISTORY list: a day label plus its entries.
class HistoryDayGroup extends Equatable {
  const HistoryDayGroup({required this.label, required this.entries});
  final String label;
  final List<HttpRequestConfigEntity> entries;

  @override
  List<Object?> get props => [label, entries];
}

/// Splits [entries] (newest-first, as `HistoryState.history` provides) into
/// ordered groups by LOCAL calendar day of `sentAt`, labelled relative to
/// [now]: 'TODAY', 'YESTERDAY', else 'MON, JUL 20' style. Comparison is by
/// calendar day, not 24-hour windows — 23:59 and 00:01 are different days.
/// Entries with a null `sentAt` land in a trailing [kEarlierGroupLabel]
/// group. Entry order within a group is preserved.
List<HistoryDayGroup> groupHistoryByDay(
  List<HttpRequestConfigEntity> entries,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final dated = <DateTime, List<HttpRequestConfigEntity>>{};
  final undated = <HttpRequestConfigEntity>[];
  for (final entry in entries) {
    final sentAt = entry.sentAt;
    if (sentAt == null) {
      undated.add(entry);
      continue;
    }
    final local = sentAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    (dated[day] ??= []).add(entry);
  }
  final days = dated.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      HistoryDayGroup(label: _labelFor(day, today), entries: dated[day]!),
    if (undated.isNotEmpty)
      HistoryDayGroup(label: kEarlierGroupLabel, entries: undated),
  ];
}

String _labelFor(DateTime day, DateTime today) {
  if (day == today) return 'TODAY';
  // Constructed (not .subtract(Duration(days: 1))): Duration arithmetic can
  // land on the wrong calendar day across a DST transition; DateTime
  // normalizes day 0 correctly.
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (day == yesterday) return 'YESTERDAY';
  return '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';
}

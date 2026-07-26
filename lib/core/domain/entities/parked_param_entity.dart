// One parked (disabled) query param row: the key/value pair removed from the
// URL when its row is unchecked, plus the row position it re-inserts at when
// re-enabled. Lives in core/domain because it rides
// HttpRequestConfigEntity.disabledParams, which tabs, collections, and
// history all share.

import 'package:equatable/equatable.dart';

/// A query param that is currently disabled ("parked"): removed from the URL
/// (the URL stays the single source of truth for *enabled* params) but kept
/// here with the [rowIndex] it re-inserts at when re-enabled. [rowIndex] is
/// clamped by the consumer at re-insert time, so stale indices are safe.
class ParkedParamEntity extends Equatable {
  const ParkedParamEntity({
    required this.key,
    required this.value,
    required this.rowIndex,
  });
  final String key;
  final String value;
  final int rowIndex;

  ParkedParamEntity copyWith({String? key, String? value, int? rowIndex}) {
    return ParkedParamEntity(
      key: key ?? this.key,
      value: value ?? this.value,
      rowIndex: rowIndex ?? this.rowIndex,
    );
  }

  @override
  List<Object?> get props => [key, value, rowIndex];
}

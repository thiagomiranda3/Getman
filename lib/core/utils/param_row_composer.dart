// Pure compose/park/unpark/decompose logic for the params tab's per-row
// enable/disable feature (B1). Query params live in the URL (single source
// of truth); a disabled param is "parked" outside the URL as a
// ParkedParamEntity carrying its display position (rowIndex). This helper
// interleaves both populations into display rows and converts edited rows
// back, so ParamsTabView stays a thin wiring layer.
//
// Gotchas: decompose matches parked entities to emitted rows by exact
// key+value content, preferring the unclaimed occurrence nearest the
// remembered rowIndex — that keeps flags on the right row through single
// deletions and duplicate content. Parked rows are read-only in the editor
// (disabledRowsReadOnly), so their content never drifts from the entities.

import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';

/// One display row of the params editor: a key/value pair plus whether it is
/// live in the URL (`enabled`) or parked in `disabledParams` (`!enabled`).
class ParamRow extends Equatable {
  const ParamRow({
    required this.key,
    required this.value,
    required this.enabled,
  });
  final String key;
  final String value;
  final bool enabled;

  @override
  List<Object?> get props => [key, value, enabled];
}

/// The (URL params, parked params) pair the composer converts to and from.
typedef ComposedParams = ({
  List<QueryParamEntity> params,
  List<ParkedParamEntity> parked,
});

class ParamRowComposer {
  ParamRowComposer._();

  /// Parked entities in deterministic order: ascending rowIndex with the
  /// original list position as tie-break (List.sort alone is not stable).
  static List<ParkedParamEntity> _sortedParked(
    List<ParkedParamEntity> parked,
  ) {
    final decorated = parked.indexed.toList()
      ..sort((a, b) {
        final byRow = a.$2.rowIndex.compareTo(b.$2.rowIndex);
        return byRow != 0 ? byRow : a.$1.compareTo(b.$1);
      });
    return [for (final (_, entity) in decorated) entity];
  }

  static int _clamp(int value, int max) =>
      value < 0 ? 0 : (value > max ? max : value);

  /// Interleaves enabled URL [params] with [parked] rows at their remembered
  /// (clamped) rowIndex. Duplicate keys are preserved in both populations.
  static List<ParamRow> compose({
    required List<QueryParamEntity> params,
    required List<ParkedParamEntity> parked,
  }) {
    final rows = [
      for (final p in params)
        ParamRow(key: p.key, value: p.value, enabled: true),
    ];
    // Insert in reverse so items with equal rowIndex maintain their original
    // list order when inserted at the same position.
    for (final p in _sortedParked(parked).reversed) {
      rows.insert(
        _clamp(p.rowIndex, rows.length),
        ParamRow(key: p.key, value: p.value, enabled: false),
      );
    }
    return rows;
  }

  /// Parks the composed row at [displayIndex]: removes it from the URL params
  /// and records it as a ParkedParamEntity at that display position. No-op
  /// (returns the inputs) when the index is out of range or already parked.
  static ComposedParams park({
    required List<QueryParamEntity> params,
    required List<ParkedParamEntity> parked,
    required int displayIndex,
  }) {
    final rows = compose(params: params, parked: parked);
    if (displayIndex < 0 || displayIndex >= rows.length) {
      return (params: params, parked: parked);
    }
    final row = rows[displayIndex];
    if (!row.enabled) return (params: params, parked: parked);
    // Position among the enabled rows = index into the params list.
    final paramIndex = rows.take(displayIndex).where((r) => r.enabled).length;
    return (
      params: [...params]..removeAt(paramIndex),
      parked: [
        ...parked,
        ParkedParamEntity(
          key: row.key,
          value: row.value,
          rowIndex: displayIndex,
        ),
      ],
    );
  }

  /// Un-parks the composed row at [displayIndex]: removes its entity from the
  /// parked list and re-inserts the pair into the URL params at the position
  /// implied by the display slot (clamped by construction). No-op when the
  /// index is out of range or the row is already enabled.
  static ComposedParams unpark({
    required List<QueryParamEntity> params,
    required List<ParkedParamEntity> parked,
    required int displayIndex,
  }) {
    final rows = compose(params: params, parked: parked);
    if (displayIndex < 0 || displayIndex >= rows.length) {
      return (params: params, parked: parked);
    }
    final row = rows[displayIndex];
    if (row.enabled) return (params: params, parked: parked);
    // The nth disabled display row is the nth entity in sorted parked order.
    final disabledOrdinal = rows
        .take(displayIndex)
        .where((r) => !r.enabled)
        .length;
    final target = _sortedParked(parked)[disabledOrdinal];
    final insertAt = rows.take(displayIndex).where((r) => r.enabled).length;
    return (
      params: [...params]
        ..insert(insertAt, QueryParamEntity(key: row.key, value: row.value)),
      parked: [...parked]..remove(target),
    );
  }

  /// Rebuilds (params, parked) from the editor's emitted rows. Rows with
  /// empty keys are dropped (they never reach canonical state) and take no
  /// display slot. Each parked entity claims the unclaimed row with identical
  /// key+value nearest its remembered rowIndex; entities with no match were
  /// deleted and are dropped. Everything unclaimed becomes an enabled param.
  static ComposedParams decompose({
    required List<(String, String)> rows,
    required List<ParkedParamEntity> parked,
  }) {
    final content = [
      for (final row in rows)
        if (row.$1.isNotEmpty) row,
    ];
    final claimed = List<bool>.filled(content.length, false);
    for (final p in _sortedParked(parked)) {
      var best = -1;
      for (var i = 0; i < content.length; i++) {
        if (claimed[i]) continue;
        if (content[i].$1 != p.key || content[i].$2 != p.value) continue;
        if (best == -1 || (i - p.rowIndex).abs() < (best - p.rowIndex).abs()) {
          best = i;
        }
      }
      if (best != -1) claimed[best] = true;
    }
    return (
      params: [
        for (var i = 0; i < content.length; i++)
          if (!claimed[i])
            QueryParamEntity(key: content[i].$1, value: content[i].$2),
      ],
      parked: [
        for (var i = 0; i < content.length; i++)
          if (claimed[i])
            ParkedParamEntity(
              key: content[i].$1,
              value: content[i].$2,
              rowIndex: i,
            ),
      ],
    );
  }
}

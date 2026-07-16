import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// What kind of value a [FieldConflict] carries. `scalar`/`mapEntry` show the
/// raw incoming/yours strings; `opaque`/`list` are whole-field (auth,
/// formFields) where the raw values aren't surfaced.
enum FieldConflictKind { scalar, mapEntry, opaque, list }

/// One field of a request/folder node that [ThreeWayMerge] could not
/// auto-resolve because both `incoming` and `yours` changed it differently
/// from `base`. Field labels mirror the vocabulary used by
/// `lib/features/collections/domain/logic/semantic_diff.dart` (e.g. "url",
/// "header 'X'", "authentication", "variable 'Y'", "child order") so the
/// resolver UI and the diff viewer read the same names.
class FieldConflict extends Equatable {
  const FieldConflict({
    required this.field,
    required this.kind,
    this.incoming,
    this.yours,
  });

  final String field;
  final FieldConflictKind kind;

  /// Null for opaque/list conflicts (auth, formFields) where the raw value
  /// isn't shown.
  final String? incoming;
  final String? yours;

  @override
  List<Object?> get props => [field, kind, incoming, yours];
}

/// Result of a field-level 3-way merge: a best-effort [merged] node with
/// every auto-resolvable field applied (unresolved fields left at the
/// `incoming` value) plus the [conflicts] that still need a user decision.
/// An empty [conflicts] list means the node fully auto-merged.
class NodeMergeResult {
  const NodeMergeResult({required this.merged, required this.conflicts});

  final CollectionNodeEntity merged;
  final List<FieldConflict> conflicts;
}

const _mapEq = MapEquality<String, String>();
const _formFieldsEq = ListEquality<MultipartFieldEntity>();
const _secretKeysEq = SetEquality<String>();

/// Pure field-level 3-way merge for collection nodes, driven by a rebase
/// conflict's base (stage 1) / incoming (stage 2, upstream) / yours (stage 3,
/// your replayed commit) versions. No IO, no Flutter — pure Dart +
/// equatable + collection only (`domain_no_infrastructure_imports`).
class ThreeWayMerge {
  const ThreeWayMerge._();

  /// Merges a request leaf. [base]/[incoming]/[yours] may each be null (e.g.
  /// [base] is null for an add/add conflict).
  static NodeMergeResult mergeRequest(
    CollectionNodeEntity? base,
    CollectionNodeEntity? incoming,
    CollectionNodeEntity? yours,
  ) {
    final skeleton = incoming ?? yours ?? base;
    if (skeleton == null) {
      throw ArgumentError(
        'mergeRequest requires at least one of base/incoming/yours',
      );
    }
    final conflicts = <FieldConflict>[];

    final name = _pick(
      conflicts,
      'name',
      base?.name,
      incoming?.name,
      yours?.name,
      (v) => v ?? '',
    );
    final isFavorite = _pick(
      conflicts,
      'favorite',
      base?.isFavorite,
      incoming?.isFavorite,
      yours?.isFavorite,
      (v) => '${v ?? false}',
    );
    final mergedConfig = _mergeConfig(
      conflicts,
      base?.config,
      incoming?.config,
      yours?.config,
    );

    final merged = skeleton.copyWith(
      name: name,
      isFavorite: isFavorite,
      config: mergedConfig,
    );
    return NodeMergeResult(merged: merged, conflicts: conflicts);
  }

  /// Merges a folder node's own fields (name, favorite, variables,
  /// secretKeys) and reports a "child order" conflict when the persisted
  /// [baseOrder]/[incomingOrder]/[yoursOrder] child-name lists diverge on all
  /// three sides. Does not reconcile the actual `children` list — that's a
  /// structural concern handled above this pure engine.
  static NodeMergeResult mergeFolder(
    CollectionNodeEntity? base,
    List<String> baseOrder,
    CollectionNodeEntity? incoming,
    List<String> incomingOrder,
    CollectionNodeEntity? yours,
    List<String> yoursOrder,
  ) {
    final skeleton = incoming ?? yours ?? base;
    if (skeleton == null) {
      throw ArgumentError(
        'mergeFolder requires at least one of base/incoming/yours',
      );
    }
    final conflicts = <FieldConflict>[];

    final name = _pick(
      conflicts,
      'name',
      base?.name,
      incoming?.name,
      yours?.name,
      (v) => v ?? '',
    );
    final isFavorite = _pick(
      conflicts,
      'favorite',
      base?.isFavorite,
      incoming?.isFavorite,
      yours?.isFavorite,
      (v) => '${v ?? false}',
    );
    final variables = _mergeMap(
      conflicts,
      'variable',
      base?.variables ?? const {},
      incoming?.variables ?? const {},
      yours?.variables ?? const {},
    );
    final secretKeys = _mergeSecretKeys(
      conflicts,
      base?.secretKeys ?? const {},
      incoming?.secretKeys ?? const {},
      yours?.secretKeys ?? const {},
    );

    // childOrder is a scalar over the joined string — reported only, not
    // reconstructed into `children` (structural, handled elsewhere).
    _pick(
      conflicts,
      'child order',
      baseOrder.join(', '),
      incomingOrder.join(', '),
      yoursOrder.join(', '),
      (v) => v,
    );

    final merged = skeleton.copyWith(
      name: name,
      isFavorite: isFavorite,
      variables: variables,
      secretKeys: secretKeys,
    );
    return NodeMergeResult(merged: merged, conflicts: conflicts);
  }

  static HttpRequestConfigEntity? _mergeConfig(
    List<FieldConflict> conflicts,
    HttpRequestConfigEntity? base,
    HttpRequestConfigEntity? incoming,
    HttpRequestConfigEntity? yours,
  ) {
    final skeleton = incoming ?? yours ?? base;
    if (skeleton == null) return null;

    final method = _pick(
      conflicts,
      'method',
      base?.method,
      incoming?.method,
      yours?.method,
      (v) => v ?? '',
    );
    final url = _pick(
      conflicts,
      'url',
      base?.url,
      incoming?.url,
      yours?.url,
      (v) => v ?? '',
    );
    final bodyTypeWire = _pick(
      conflicts,
      'body type',
      base?.bodyType.wire,
      incoming?.bodyType.wire,
      yours?.bodyType.wire,
      (v) => v ?? '',
    );
    final body = _pick(
      conflicts,
      'body',
      base?.body,
      incoming?.body,
      yours?.body,
      (v) => v ?? '',
    );
    final graphqlVariables = _pick(
      conflicts,
      'GraphQL variables',
      base?.graphqlVariables,
      incoming?.graphqlVariables,
      yours?.graphqlVariables,
      (v) => v ?? '',
    );
    final bodyFilePath = _pick(
      conflicts,
      'binary file',
      base?.bodyFilePath,
      incoming?.bodyFilePath,
      yours?.bodyFilePath,
      (v) => v ?? '',
    );
    final headers = _mergeMap(
      conflicts,
      'header',
      base?.headers ?? const {},
      incoming?.headers ?? const {},
      yours?.headers ?? const {},
    );
    final auth = _mergeAuth(
      conflicts,
      base?.auth ?? const {},
      incoming?.auth ?? const {},
      yours?.auth ?? const {},
    );
    final formFields = _mergeFormFields(
      conflicts,
      base?.formFields ?? const [],
      incoming?.formFields ?? const [],
      yours?.formFields ?? const [],
    );

    return skeleton.copyWith(
      method: method,
      url: url,
      headers: headers,
      body: body,
      auth: auth,
      bodyType: BodyType.fromWire(bodyTypeWire),
      formFields: formFields,
      bodyFilePath: bodyFilePath,
      graphqlVariables: graphqlVariables,
    );
  }

  /// Core per-field rule: `incoming == yours` -> agree; `incoming == base` ->
  /// auto-merge `yours`; `yours == base` -> auto-merge `incoming`; else -> a
  /// true conflict (value left at `incoming`, both candidates recorded).
  static T _pick<T>(
    List<FieldConflict> conflicts,
    String field,
    T base,
    T incoming,
    T yours,
    String Function(T value) show, {
    FieldConflictKind kind = FieldConflictKind.scalar,
  }) {
    if (incoming == yours) return incoming;
    if (incoming == base) return yours;
    if (yours == base) return incoming;
    conflicts.add(
      FieldConflict(
        field: field,
        kind: kind,
        incoming: show(incoming),
        yours: show(yours),
      ),
    );
    return incoming;
  }

  /// Maps (headers, folder variables) are merged per key over the union of
  /// keys from all three sides, applying [_pick]'s rule to each key.
  static Map<String, String> _mergeMap(
    List<FieldConflict> conflicts,
    String label,
    Map<String, String> base,
    Map<String, String> incoming,
    Map<String, String> yours,
  ) {
    final result = <String, String>{};
    for (final key in {...base.keys, ...incoming.keys, ...yours.keys}) {
      final b = base[key];
      final i = incoming[key];
      final y = yours[key];
      String? resolved;
      if (i == y) {
        resolved = i;
      } else if (i == b) {
        resolved = y;
      } else if (y == b) {
        resolved = i;
      } else {
        conflicts.add(
          FieldConflict(
            field: "$label '$key'",
            kind: FieldConflictKind.mapEntry,
            incoming: i,
            yours: y,
          ),
        );
        resolved = i;
      }
      if (resolved != null) result[key] = resolved;
    }
    return result;
  }

  static Set<String> _mergeSecretKeys(
    List<FieldConflict> conflicts,
    Set<String> base,
    Set<String> incoming,
    Set<String> yours,
  ) {
    if (_secretKeysEq.equals(incoming, yours)) return incoming;
    if (_secretKeysEq.equals(incoming, base)) return yours;
    if (_secretKeysEq.equals(yours, base)) return incoming;
    conflicts.add(
      const FieldConflict(field: 'secret keys', kind: FieldConflictKind.list),
    );
    return incoming;
  }

  static Map<String, String> _mergeAuth(
    List<FieldConflict> conflicts,
    Map<String, String> base,
    Map<String, String> incoming,
    Map<String, String> yours,
  ) {
    if (_mapEq.equals(incoming, yours)) return incoming;
    if (_mapEq.equals(incoming, base)) return yours;
    if (_mapEq.equals(yours, base)) return incoming;
    conflicts.add(
      const FieldConflict(
        field: 'authentication',
        kind: FieldConflictKind.opaque,
      ),
    );
    return incoming;
  }

  static List<MultipartFieldEntity> _mergeFormFields(
    List<FieldConflict> conflicts,
    List<MultipartFieldEntity> base,
    List<MultipartFieldEntity> incoming,
    List<MultipartFieldEntity> yours,
  ) {
    if (_formFieldsEq.equals(incoming, yours)) return incoming;
    if (_formFieldsEq.equals(incoming, base)) return yours;
    if (_formFieldsEq.equals(yours, base)) return incoming;
    conflicts.add(
      const FieldConflict(field: 'form fields', kind: FieldConflictKind.list),
    );
    return incoming;
  }
}

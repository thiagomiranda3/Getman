import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

enum ChangeKind { added, removed, changed }

/// One field-level change in a semantic node diff. [before]/[after] are shown
/// verbatim in the diff view; leave both null for masked/opaque changes (auth).
class FieldChange extends Equatable {
  const FieldChange({
    required this.field,
    required this.kind,
    this.before,
    this.after,
  });
  final String field;
  final ChangeKind kind;
  final String? before;
  final String? after;

  @override
  List<Object?> get props => [field, kind, before, after];
}

/// An ordered list of field changes between two versions of a node.
class SemanticDiff extends Equatable {
  const SemanticDiff(this.changes);
  final List<FieldChange> changes;
  bool get isEmpty => changes.isEmpty;

  @override
  List<Object?> get props => [changes];
}

const _mapEq = MapEquality<String, String>();
const _listEq = ListEquality<Object?>();

ChangeKind _kind(Object? before, Object? after) => before == null
    ? ChangeKind.added
    : after == null
    ? ChangeKind.removed
    : ChangeKind.changed;

void _scalar(
  List<FieldChange> out,
  String field,
  String? before,
  String? after,
) {
  final b = (before?.isEmpty ?? true) ? null : before;
  final a = (after?.isEmpty ?? true) ? null : after;
  if (b == a) return;
  out.add(FieldChange(field: field, kind: _kind(b, a), before: b, after: a));
}

void _mapPerKey(
  List<FieldChange> out,
  String label,
  Map<String, String> before,
  Map<String, String> after,
) {
  for (final key in {...before.keys, ...after.keys}) {
    final b = before[key];
    final a = after[key];
    if (b == a) continue;
    out.add(
      FieldChange(
        field: "$label '$key'",
        kind: _kind(b, a),
        before: b,
        after: a,
      ),
    );
  }
}

/// Diffs the workspace-serialized fields of a request config (see
/// WorkspaceCollectionSerializer._configToJson). `kind` and response fields are
/// not persisted, so they are never diffed. Auth is reported as changed without
/// its (secret) values.
class RequestConfigDiff {
  const RequestConfigDiff._();

  static SemanticDiff diff(
    HttpRequestConfigEntity? before,
    HttpRequestConfigEntity? after,
  ) {
    final out = <FieldChange>[];
    _scalar(out, 'method', before?.method, after?.method);
    _scalar(out, 'url', before?.url, after?.url);
    _scalar(out, 'body type', before?.bodyType.name, after?.bodyType.name);
    _scalar(out, 'body', before?.body, after?.body);
    _scalar(
      out,
      'GraphQL variables',
      before?.graphqlVariables,
      after?.graphqlVariables,
    );
    _scalar(out, 'binary file', before?.bodyFilePath, after?.bodyFilePath);
    _mapPerKey(
      out,
      'header',
      before?.headers ?? const {},
      after?.headers ?? const {},
    );

    final beforeAuth = before?.auth ?? const {};
    final afterAuth = after?.auth ?? const {};
    if (!_mapEq.equals(beforeAuth, afterAuth)) {
      out.add(
        FieldChange(
          field: 'authentication',
          kind: _kind(
            beforeAuth.isEmpty ? null : beforeAuth,
            afterAuth.isEmpty ? null : afterAuth,
          ),
        ),
      );
    }

    final beforeForm = before?.formFields ?? const [];
    final afterForm = after?.formFields ?? const [];
    if (!_listEq.equals(beforeForm, afterForm)) {
      out.add(
        FieldChange(
          field: 'form fields',
          kind: _kind(
            beforeForm.isEmpty ? null : beforeForm,
            afterForm.isEmpty ? null : afterForm,
          ),
          before: beforeForm.isEmpty ? null : '${beforeForm.length} field(s)',
          after: afterForm.isEmpty ? null : '${afterForm.length} field(s)',
        ),
      );
    }
    return SemanticDiff(out);
  }
}

/// Diffs the workspace-serialized fields of a folder node (name, favorite,
/// variables, child order). Description is not persisted, so it is not diffed.
class FolderNodeDiff {
  const FolderNodeDiff._();

  static SemanticDiff diff(
    CollectionNodeEntity? before,
    CollectionNodeEntity? after,
  ) {
    final out = <FieldChange>[];
    _scalar(out, 'name', before?.name, after?.name);
    _scalar(
      out,
      'favorite',
      before == null ? null : '${before.isFavorite}',
      after == null ? null : '${after.isFavorite}',
    );
    _mapPerKey(
      out,
      'variable',
      before?.variables ?? const {},
      after?.variables ?? const {},
    );

    final beforeOrder =
        before?.children.map((c) => c.name).toList() ?? const [];
    final afterOrder =
        after?.children.map((c) => c.name).toList() ?? const [];
    if (!_listEq.equals(beforeOrder, afterOrder)) {
      out.add(
        FieldChange(
          field: 'child order',
          kind: ChangeKind.changed,
          before: beforeOrder.join(', '),
          after: afterOrder.join(', '),
        ),
      );
    }
    return SemanticDiff(out);
  }
}

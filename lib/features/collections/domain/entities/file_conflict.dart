import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/logic/three_way_merge.dart';

/// What kind of conflict a workspace file is in, as classified by the
/// conflict service after a rebase halts. `request`/`folder` are
/// field-level (resolved via [ThreeWayMerge]); `addAdd`/`deleteModify`/
/// `structural` are coarse — resolved by picking a whole-file side.
enum ConflictKind { request, folder, addAdd, deleteModify, structural }

/// One conflicted file surfaced by `ConflictService.currentConflicts`.
/// `node` is deliberately excluded from props — it's compared by identity,
/// not value; only path + kind determine conflict identity/equality.
// ignore: equatable_props_complete
class FileConflict extends Equatable {
  const FileConflict({
    required this.path,
    required this.kind,
    this.node,
    this.deletedSide,
  });

  final String path;
  final ConflictKind kind;

  /// Present for [ConflictKind.request]/[ConflictKind.folder] (field-level);
  /// null for coarse kinds.
  final NodeMergeResult? node;

  /// For [ConflictKind.deleteModify] only: which side deleted the file (the
  /// side whose merge stage is absent). Null for every other [kind]. Drives
  /// the coarse tile's button orientation — "Accept the deletion" always maps
  /// to this side, never hardcoded to incoming/yours.
  final FileSide? deletedSide;

  bool get isFieldLevel => node != null;

  @override
  // node compared by identity is fine.
  List<Object?> get props => [path, kind, deletedSide];
}

/// The side of a whole-file (coarse) conflict the user picked.
enum FileSide { incoming, yours }

/// One user decision for a conflicted file. For field-level conflicts:
/// a map of field-label → chosen value (an edited string, or the picked
/// incoming/yours value). For coarse conflicts: a whole-file side.
class FileResolution extends Equatable {
  const FileResolution({
    required this.path,
    this.fieldChoices = const {},
    this.wholeFile,
  });

  final String path;

  /// field-label → resolved string value.
  final Map<String, String> fieldChoices;

  /// Set for coarse/structural files.
  final FileSide? wholeFile;

  @override
  List<Object?> get props => [path, fieldChoices, wholeFile];
}

/// Outcome of asking the conflict service to continue an in-progress rebase.
enum RebaseStep { done, moreConflicts }

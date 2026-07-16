import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';
import 'package:getman/features/collections/domain/logic/three_way_merge.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_event.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_state.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

/// Drives the resolve → continue loop for an in-progress rebase, opened from
/// the branch chip when a pull halts on conflicts (`GitSyncState.
/// conflictToken`). One `ConflictState.conflicts` batch is one paused
/// commit's worth of files; RESOLVE & CONTINUE may surface another batch
/// before the rebase finishes.
class ConflictResolutionDialog {
  const ConflictResolutionDialog._();

  static Future<void> show(BuildContext context, {required String root}) {
    // Capture both blocs before the dialog's own subtree: the conflict list
    // lives under ConflictBloc; a successful resolve nudges the branch chip
    // via GitSyncBloc (widget-layer coordination — no bloc→bloc coupling).
    final conflict = context.read<ConflictBloc>();
    final git = context.read<GitSyncBloc>();
    // Also re-provided (mirroring conflict/git above): the fullscreen route
    // path in showResponsiveDialog pushes onto the root Navigator, so the
    // RESOLVE & CONTINUE identity read below needs SettingsBloc reachable
    // from that subtree.
    final settings = context.read<SettingsBloc>();
    return showResponsiveDialog<void>(
      context,
      barrierDismissible: false,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<ConflictBloc>.value(value: conflict),
          BlocProvider<GitSyncBloc>.value(value: git),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: ConflictResolutionBody(root: root),
      ),
    );
  }
}

/// The dialog content (public for widget testing). Stateful to hold the
/// in-progress picks for the current batch — the bloc only knows resolved
/// choices once RESOLVE & CONTINUE is dispatched.
class ConflictResolutionBody extends StatefulWidget {
  const ConflictResolutionBody({required this.root, super.key});
  final String root;

  @override
  State<ConflictResolutionBody> createState() => _ConflictResolutionBodyState();
}

class _ConflictResolutionBodyState extends State<ConflictResolutionBody> {
  // path -> field label -> pick. Field-level conflicts only.
  final Map<String, Map<String, FieldPick>> _fieldPicks = {};
  // path -> whole-file side. Coarse conflicts only.
  final Map<String, FileSide> _wholeFilePicks = {};
  int _picksForBatch = -1;
  // Set by _cancel before dispatching AbortRebase. _cancel itself does NOT
  // pop — if the abort fails (rare), the dialog must stay open (with the GIT
  // ERROR dialog on top) so the user can retry rather than being left with a
  // wedged rebase and no UI. The done-listener pops once the abort actually
  // resolves to ConflictStatus.done, and — because this was an abort, not a
  // resolve — skips the resolve-flow's "Conflicts resolved." snackbar and the
  // tree-reload dispatch (pre-pull state already matches Hive).
  bool _aborting = false;

  @override
  void initState() {
    super.initState();
    context.read<ConflictBloc>().add(LoadConflicts(widget.root));
  }

  /// Picks are scoped to one batch of conflicts — a new batch is a different
  /// set of files/fields entirely, so stale picks from the previous commit
  /// must not leak into the next one.
  void _resetPicksIfNewBatch(int batch) {
    if (batch == _picksForBatch) return;
    _picksForBatch = batch;
    _fieldPicks.clear();
    _wholeFilePicks.clear();
  }

  void _onFieldPick(String path, String field, FieldPick pick) {
    setState(() => _fieldPicks.putIfAbsent(path, () => {})[field] = pick);
  }

  void _onWholeFilePick(String path, FileSide side) {
    setState(() => _wholeFilePicks[path] = side);
  }

  bool _allPicked(List<FileConflict> conflicts) {
    for (final fc in conflicts) {
      if (fc.node != null) {
        final fieldConflicts = fc.node!.conflicts;
        if (fieldConflicts.isEmpty) continue; // auto-merged
        final picks = _fieldPicks[fc.path];
        if (picks == null) return false;
        for (final fieldConflict in fieldConflicts) {
          if (!picks.containsKey(fieldConflict.field)) return false;
        }
      } else {
        if (_wholeFilePicks[fc.path] == null) return false;
      }
    }
    return true;
  }

  void _submit(BuildContext context, List<FileConflict> conflicts) {
    final resolutions = [
      for (final fc in conflicts)
        if (fc.node != null)
          FileResolution(
            path: fc.path,
            fieldChoices: {
              for (final entry in (_fieldPicks[fc.path] ?? const {}).entries)
                entry.key: entry.value.value,
            },
          )
        else
          FileResolution(path: fc.path, wholeFile: _wholeFilePicks[fc.path]),
    ];
    final identity = context.read<SettingsBloc>().state.settings;
    context.read<ConflictBloc>().add(
      ResolveAndContinue(
        widget.root,
        resolutions,
        authorName: identity.gitUserName,
        authorEmail: identity.gitUserEmail,
      ),
    );
  }

  void _cancel(BuildContext context) {
    _aborting = true;
    context.read<ConflictBloc>().add(AbortRebase(widget.root));
    // Does NOT pop here — see the _aborting doc comment. The done-listener
    // pops once the abort actually completes; if it fails instead, the
    // dialog stays open and the GIT ERROR dialog surfaces on top of it.
  }

  void _showError(BuildContext context, String message) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('conflict_error_dialog'),
          title: const Text('GIT ERROR'),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocConsumer<ConflictBloc, ConflictState>(
      listenWhen: (p, c) =>
          (c.status == ConflictStatus.error &&
              p.errorMessage != c.errorMessage &&
              c.errorMessage != null) ||
          (c.status == ConflictStatus.done && p.status != ConflictStatus.done),
      listener: (context, state) {
        if (state.status == ConflictStatus.done) {
          if (_aborting) {
            // The abort itself resolved to `done`: pop now (CANCEL no
            // longer pops synchronously — see _cancel), without the
            // resolve-flow's "Conflicts resolved." snackbar or a tree
            // reload — pre-pull state already matches Hive, there is
            // nothing to reload.
            unawaited(Navigator.of(context).maybePop());
            return;
          }
          // Capture before popping: the dialog's own context is about to be
          // deactivated, so the snackbar goes through the captured messenger.
          final messenger = ScaffoldMessenger.of(context);
          final gitBloc = context.read<GitSyncBloc>();
          unawaited(Navigator.of(context).maybePop());
          showAppSnackBarVia(messenger, 'Conflicts resolved.');
          // ConflictsResolved (not LoadBranchStatus) both refreshes branch
          // status AND bumps reloadToken so BranchSyncListener reloads the
          // merged tree — otherwise the resolved files sit on disk while
          // Hive still holds the pre-pull tree, and the next edit's mirror
          // silently reverts the merge.
          gitBloc.add(ConflictsResolved(widget.root));
        } else if (state.status == ConflictStatus.error) {
          _showError(context, state.errorMessage!);
        }
      },
      builder: (context, state) {
        if (state.status == ConflictStatus.ready ||
            state.status == ConflictStatus.error) {
          _resetPicksIfNewBatch(state.batch);
        }
        final busy = state.isBusy;
        return ResponsiveDialogScaffold(
          title: Text('Resolving conflicts — commit ${state.batch + 1}'),
          content: SizedBox(
            width: layout.dialogWidth,
            height: layout.settingsDialogHeight,
            child: _content(context, state),
          ),
          actions: [
            TextButton(
              key: const ValueKey('conflict_cancel'),
              onPressed: busy ? null : () => _cancel(context),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              key: const ValueKey('conflict_resolve'),
              onPressed: (!busy && _allPicked(state.conflicts))
                  ? () => _submit(context, state.conflicts)
                  : null,
              child: const Text('RESOLVE & CONTINUE'),
            ),
          ],
        );
      },
    );
  }

  Widget _content(BuildContext context, ConflictState state) {
    switch (state.status) {
      case ConflictStatus.initial:
      case ConflictStatus.loading:
      case ConflictStatus.resolving:
        return const Center(child: CircularProgressIndicator());
      case ConflictStatus.done:
        return const SizedBox.shrink();
      case ConflictStatus.ready:
      case ConflictStatus.error:
        final layout = context.appLayout;
        return ListView.separated(
          itemCount: state.conflicts.length,
          separatorBuilder: (_, _) => SizedBox(height: layout.tabSpacing),
          itemBuilder: (context, i) => _fileTile(context, state.conflicts[i]),
        );
    }
  }

  Widget _fileTile(BuildContext context, FileConflict fc) {
    if (fc.node != null) {
      return _FieldLevelTile(
        key: ValueKey(fc.path),
        conflict: fc,
        picks: _fieldPicks[fc.path] ?? const {},
        onPick: (field, pick) => _onFieldPick(fc.path, field, pick),
      );
    }
    return _CoarseTile(
      conflict: fc,
      picked: _wholeFilePicks[fc.path],
      onPick: (side) => _onWholeFilePick(fc.path, side),
    );
  }
}

/// One resolved field: which side was picked, and the (possibly
/// user-edited) resolved value. For opaque/list conflicts [value] is always
/// the literal marker `'incoming'`/`'yours'` — never a real value.
class FieldPick {
  const FieldPick({required this.side, required this.value});
  final FileSide side;
  final String value;
}

class _FieldLevelTile extends StatelessWidget {
  const _FieldLevelTile({
    required this.conflict,
    required this.picks,
    required this.onPick,
    super.key,
  });
  final FileConflict conflict;
  final Map<String, FieldPick> picks;
  final void Function(String field, FieldPick pick) onPick;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final node = conflict.node!;
    return Container(
      key: ValueKey('conflict_file_${conflict.path}'),
      padding: EdgeInsets.all(layout.tabSpacing),
      decoration: context.appDecoration.panelBox(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            conflict.path,
            style: TextStyle(
              fontWeight: context.appTypography.titleWeight,
              fontFamily: context.appTypography.codeFontFamily,
            ),
          ),
          SizedBox(height: layout.tabSpacing),
          if (node.conflicts.isEmpty)
            Text(
              'Auto-merged.',
              key: ValueKey('conflict_automerged_${conflict.path}'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final fieldConflict in node.conflicts)
              Padding(
                padding: EdgeInsets.only(top: layout.tabSpacing),
                child: _FieldConflictRow(
                  key: ValueKey('${conflict.path}_${fieldConflict.field}'),
                  path: conflict.path,
                  fieldConflict: fieldConflict,
                  pick: picks[fieldConflict.field],
                  onPick: (pick) => onPick(fieldConflict.field, pick),
                ),
              ),
        ],
      ),
    );
  }
}

class _FieldConflictRow extends StatefulWidget {
  const _FieldConflictRow({
    required this.path,
    required this.fieldConflict,
    required this.pick,
    required this.onPick,
    super.key,
  });
  final String path;
  final FieldConflict fieldConflict;
  final FieldPick? pick;
  final ValueChanged<FieldPick> onPick;

  @override
  State<_FieldConflictRow> createState() => _FieldConflictRowState();
}

class _FieldConflictRowState extends State<_FieldConflictRow> {
  TextEditingController? _textController;
  CodeLineEditingController? _codeController;
  FileSide? _controllerSide;

  bool get _isBody => widget.fieldConflict.field == 'body';

  /// `scalar`/`mapEntry` show an editable value; `opaque`/`list` (auth, form
  /// fields) never do — the CRITICAL CONTRACT is that those store only the
  /// literal `'incoming'`/`'yours'` marker, never free text.
  bool get _editable =>
      widget.fieldConflict.kind == FieldConflictKind.scalar ||
      widget.fieldConflict.kind == FieldConflictKind.mapEntry;

  @override
  void initState() {
    super.initState();
    if (!_editable) return;
    if (_isBody) {
      _codeController = createJsonCodeController()..addListener(_onCodeChanged);
    } else {
      _textController = TextEditingController()..addListener(_onTextChanged);
    }
    final pick = widget.pick;
    if (pick != null) {
      _controllerSide = pick.side;
      _setControllerText(pick.value);
    }
  }

  @override
  void dispose() {
    _textController?.dispose();
    _codeController?.dispose();
    super.dispose();
  }

  void _setControllerText(String text) {
    if (_isBody) {
      _codeController!.text = text;
    } else {
      _textController!.text = text;
    }
  }

  void _onTextChanged() {
    final side = _controllerSide;
    if (side == null) return;
    widget.onPick(FieldPick(side: side, value: _textController!.text));
  }

  void _onCodeChanged() {
    final side = _controllerSide;
    if (side == null) return;
    widget.onPick(FieldPick(side: side, value: _codeController!.text));
  }

  void _pickSide(FileSide side) {
    final fc = widget.fieldConflict;
    if (_editable) {
      final value = side == FileSide.incoming
          ? (fc.incoming ?? '')
          : (fc.yours ?? '');
      _controllerSide = side;
      _setControllerText(value);
      widget.onPick(FieldPick(side: side, value: value));
    } else {
      final value = side == FileSide.incoming ? 'incoming' : 'yours';
      widget.onPick(FieldPick(side: side, value: value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final fc = widget.fieldConflict;
    final pick = widget.pick;
    final keyBase = '${widget.path}_${fc.field}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fc.field,
          style: TextStyle(fontWeight: context.appTypography.bodyWeight),
        ),
        SizedBox(height: layout.tabSpacing / 2),
        Row(
          children: [
            Expanded(
              child: _SideButton(
                key: ValueKey('take_incoming_$keyBase'),
                label: 'TAKE INCOMING',
                selected: pick?.side == FileSide.incoming,
                onTap: () => _pickSide(FileSide.incoming),
              ),
            ),
            SizedBox(width: layout.tabSpacing),
            Expanded(
              child: _SideButton(
                key: ValueKey('keep_yours_$keyBase'),
                label: 'KEEP YOURS',
                selected: pick?.side == FileSide.yours,
                onTap: () => _pickSide(FileSide.yours),
              ),
            ),
          ],
        ),
        if (_editable && pick != null)
          Padding(
            padding: EdgeInsets.only(top: layout.tabSpacing),
            child: _isBody
                ? SizedBox(
                    key: ValueKey('edit_body_$keyBase'),
                    height: 160,
                    child: JsonCodeEditor(controller: _codeController!),
                  )
                : TextField(
                    key: ValueKey('edit_field_$keyBase'),
                    controller: _textController,
                  ),
          ),
      ],
    );
  }
}

class _CoarseTile extends StatelessWidget {
  const _CoarseTile({
    required this.conflict,
    required this.picked,
    required this.onPick,
  });
  final FileConflict conflict;
  final FileSide? picked;
  final ValueChanged<FileSide> onPick;

  bool get _isDeleteModify => conflict.kind == ConflictKind.deleteModify;

  /// For a delete/modify conflict, labels by orientation instead of a
  /// hardcoded side: the side that actually deleted the file
  /// ([FileConflict.deletedSide]) always reads "Accept the deletion"; the
  /// other side always reads "Keep the edited request" — whichever of
  /// incoming/yours that happens to be. Hardcoding these to
  /// incoming/yours inverted the buttons whenever *you* were the deleting
  /// side (FIX C1).
  String _label(FileSide side, String defaultLabel) {
    if (!_isDeleteModify) return defaultLabel;
    return side == conflict.deletedSide
        ? 'Accept the deletion'
        : 'Keep the edited request';
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Container(
      key: ValueKey('conflict_file_${conflict.path}'),
      padding: EdgeInsets.all(layout.tabSpacing),
      decoration: context.appDecoration.panelBox(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            conflict.path,
            style: TextStyle(
              fontWeight: context.appTypography.titleWeight,
              fontFamily: context.appTypography.codeFontFamily,
            ),
          ),
          SizedBox(height: layout.tabSpacing),
          Row(
            children: [
              Expanded(
                child: _SideButton(
                  key: ValueKey('take_incoming_${conflict.path}'),
                  label: _label(FileSide.incoming, 'TAKE INCOMING'),
                  selected: picked == FileSide.incoming,
                  onTap: () => onPick(FileSide.incoming),
                ),
              ),
              SizedBox(width: layout.tabSpacing),
              Expanded(
                child: _SideButton(
                  key: ValueKey('keep_yours_${conflict.path}'),
                  label: _label(FileSide.yours, 'KEEP YOURS'),
                  selected: picked == FileSide.yours,
                  onTap: () => onPick(FileSide.yours),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single two-state pick button: filled when selected, outlined otherwise.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton(onPressed: onTap, child: Text(label))
        : OutlinedButton(onPressed: onTap, child: Text(label));
  }
}

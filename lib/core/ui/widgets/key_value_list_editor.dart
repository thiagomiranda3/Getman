// Generic editable key/value row list backing params (ordered list),
// headers (map), and environment variables (map) — the canonical type is
// supplied via decode/encode/equals codecs so all three share this one
// editor.
//
// Gotchas: never bypass with a bespoke row editor — _lastEmitted
// echo-suppression is what keeps focus and half-typed text alive across the
// BLoC round-trip (a matching echo does NOT reset the row controllers).
// Optional secretKeys/onSecretKeysChanged adds the per-row lock+reveal
// affordance; wired only by the env editor, left null for params/headers.
// Optional rowEnabled/onToggleEnabled adds a leading enable/disable checkbox
// column (B1, params/headers); flags are seeded from rowEnabled on every
// controller rebuild and tracked internally between rebuilds so they follow
// rows through deletes. The trailing auto-blank row never shows a checkbox.
// Optional onReorder/onDuplicate (B2) add a drag handle + duplicate button
// per data row, gated additionally on rowEnabled (a parked/disabled row gets
// neither — checkbox and delete stay live). Never shown on the trailing
// auto-blank row.
//
// Enabled-subsequence pre-move (2B.3 review fix): on drop, _handleReorder
// locally repositions its row controllers BEFORE calling the host — but only
// within the enabled-row subsequence (_repositionWithinEnabledRows); disabled
// (e.g. parked) rows stay pinned at their absolute slot. A flat/naive
// pre-move (moving whatever was dragged straight to the drop slot,
// disabled rows included) caused a PERSISTENT visual desync: when an enabled
// row's drag crossed only disabled/parked rows (no net enabled-order
// change), the naive pre-move still visually reordered the rows, but hosts
// that virtually exclude disabled rows from their reorder space (params'
// parked rows ride outside the URL sequence) correctly treated it as a
// no-op — and a genuine no-op dispatch (byte-identical entity) makes
// Bloc.emit suppress the state entirely, so didUpdateWidget never runs to
// correct the wrong visual order. Scoping the pre-move to the enabled
// subsequence fixes this at the source: when the enabled sequence's relative
// order doesn't change, this method computes zero movement, so nothing
// diverges in the first place. didUpdateWidget's existing equals-based
// resync (see _sameDecodedOrder below) remains a second line of defense for
// any case the pre-move doesn't cover (e.g. an external replace) — the two
// mechanisms agree by construction, since both ultimately mirror the host's
// own display-index composition.
//
// Keyless-row reconcile (didUpdateWidget): echo suppression alone cannot
// keep a cleared-key row alive across a host mutation whose echo genuinely
// differs (params toggle — ParamRow.enabled is order-significant in its
// equals — or any reorder/duplicate): the full rebuild re-seeds from
// canonical items, which already dropped the keyless row when its clear was
// emitted, destroying the row AND its typed value. didUpdateWidget therefore
// snapshots editor-only rows first (empty key text, excluding the trailing
// auto-blank) — their positions, value TEXTS and enabled flags, never the
// controller instances (those are disposed by _disposeControllers) — and
// reinserts equivalent fresh controllers at the clamped remembered positions
// after _initControllers. Data preservation is the contract; focus is not
// (row identity is the controller, so a rebuilt row re-mounts).
//
// Host indexing is host-parameterized (KeyValueHostIndexing): map-backed
// hosts collapse duplicate keys — the map entry's POSITION comes from the
// FIRST occurrence, its VALUE from the last (Dart map-literal semantics) —
// and the env editor's encode also trims keys, so translating editor→host
// indices by skipping only empty-key rows goes off by one as soon as a
// duplicate-key (or, for env, whitespace-key) row is alive above the
// operated row (echo suppression keeps such rows alive on purpose).
// _hostIndexFor therefore counts map-host rows through the host's own codec
// (decode(encode(prefix)).length — first-occurrence + canonicalization for
// free); `auto` infers map hosts from the runtime type of items, so list
// hosts (params) keep the original every-non-empty-key-counts rule.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_text_field.dart';
import 'package:getman/core/utils/layered_variable_context.dart';

/// How [KeyValueListEditor] translates its own row indices into the host's
/// canonical row indices for [KeyValueListEditor.onReorder],
/// [KeyValueListEditor.onDuplicate] and [KeyValueListEditor.onToggleEnabled]
/// (see `_hostIndexFor`). Host-parameterized because list- and map-backed
/// hosts disagree on which editor rows exist canonically.
enum KeyValueHostIndexing {
  /// Infer from the runtime type of [KeyValueListEditor.items]: `Map`-backed
  /// items get [map], everything else gets [list]. The default — it selects
  /// exactly the right semantics for every current host (params →
  /// `List<ParamRow>` → [list]; headers / env vars / collection vars →
  /// `Map<String, String>` → [map]) without any host wiring.
  ///
  /// Host wiring note (later task): hosts may pin this explicitly —
  /// `params_tab_view.dart` → [list]; `headers_tab_view.dart`,
  /// `environment_editor.dart`, `collection_variables_dialog.dart` → [map].
  /// Until then [auto]'s inference already yields those values.
  auto,

  /// List-backed host (params): every non-empty-key row is one host row,
  /// duplicate keys included (duplicates are legal in a query string).
  /// Matches the original empty-key-skipping translation exactly.
  list,

  /// Insertion-ordered-map-backed host (headers / env vars): encode collapses
  /// duplicate keys into a single entry whose POSITION is the first
  /// occurrence's and whose VALUE is the last occurrence's (Dart map-literal
  /// semantics), so a row counts for host indexing iff it is encode-visible
  /// AND the first occurrence of its canonical key. Both properties are
  /// derived through the host's own [KeyValueListEditor.encode]/
  /// [KeyValueListEditor.decode] codec rather than re-implemented, so
  /// per-host key canonicalization (the env editor trims keys in encode)
  /// comes along for free. Requires `encode` to be a pure function of the
  /// rows it is given — true for every map host; params' encode is not
  /// (it re-attaches parked rows), which is why [list] never counts through
  /// the codec.
  map,
}

/// Generic editable key/value row list backing the params, headers, and
/// environment-variable editors. The canonical value type [T] (ordered list,
/// map, …) is supplied via a codec:
///
/// - [decode] turns [items] into ordered (key, value) rows;
/// - [encode] turns the current rows back into a [T] for [onChanged];
/// - [equals] compares two [T]s in canonical space.
///
/// Echo suppression: when the parent echoes back exactly what this editor
/// just emitted (the usual BLoC round-trip), the text controllers are NOT
/// rebuilt — that keeps focus and half-typed state alive. Only a genuinely
/// external change resets the rows. See CLAUDE.md's "Global gotchas" section.
class KeyValueListEditor<T extends Object> extends StatefulWidget {
  const KeyValueListEditor({
    required this.items,
    required this.onChanged,
    required this.decode,
    required this.encode,
    required this.equals,
    super.key,
    this.secretKeys,
    this.onSecretKeysChanged,
    this.variableContext,
    this.fieldPrefix,
    this.rowEnabled,
    this.onToggleEnabled,
    this.disabledRowsReadOnly = false,
    this.onReorder,
    this.onDuplicate,
    this.hostIndexing = KeyValueHostIndexing.auto,
  });
  final T items;
  final ValueChanged<T> onChanged;
  final List<(String, String)> Function(T items) decode;
  final T Function(List<(String, String)> rows) encode;
  final bool Function(T a, T b) equals;

  /// Names flagged secret. When non-null, each row shows a lock toggle and
  /// secret rows obscure their value (with a reveal toggle). Null (the default,
  /// used by params/headers) disables all secret affordances.
  final Set<String>? secretKeys;

  /// Called with the new secret-key set when a row's lock is toggled.
  final ValueChanged<Set<String>>? onSecretKeysChanged;

  /// When non-null, value fields highlight `{{var}}` tokens, show a hover
  /// popover resolving them, and offer autocomplete suggestions from the
  /// layered (env + collection + dynamic) variable context. Params and headers
  /// pass a context (highlighting enabled); the env editor and other consumers
  /// pass null, leaving value fields as plain text. Note: this is unrelated to
  /// [secretKeys], which toggles per-row secret obscuring in the env editor.
  final LayeredVariableContext? variableContext;

  /// When set, each row's key/value [TextField] gets a stable
  /// `ValueKey('<prefix>_key_<index>')` / `ValueKey('<prefix>_val_<index>')` so
  /// E2E tests can target a specific row in a specific editor (params/headers/
  /// env vars all use this widget). Null (the default) leaves fields unkeyed.
  final String? fieldPrefix;

  /// Seed-time enabled flag per decoded row index. When this and
  /// [onToggleEnabled] are both non-null every row (except the trailing
  /// auto-blank) shows a leading enable/disable checkbox. Flags are re-seeded
  /// from this callback whenever the controllers are rebuilt from [items];
  /// between rebuilds the editor tracks them itself (toggle flips, delete
  /// removes, new rows default to enabled) so they stay aligned with rows.
  final bool Function(int index)? rowEnabled;

  /// Called after a checkbox toggle with the row's display index, its current
  /// key/value text, and the new enabled state. The host owns canonical state
  /// (URL park/unpark, disabled-header-key set) and echoes it back via
  /// [items]. Positional `enabled` matches the natural (index, key, value,
  /// enabled) call-site shape this contract is built around (see task brief).
  // ignore: avoid_positional_boolean_parameters
  final void Function(int index, String key, String value, bool enabled)?
  onToggleEnabled;

  /// When true, rows whose checkbox is off render read-only (params: parked
  /// rows live outside the URL, so a free-text edit has nowhere to go).
  /// Headers leave this false — disabled header rows stay editable.
  final bool disabledRowsReadOnly;

  /// When non-null, every row except the trailing auto-blank one shows a
  /// drag handle ([ReorderableDragStartListener] — immediate, desktop
  /// friendly, no long-press) and rows can be reordered. Called with
  /// (oldIndex, newIndex) in decoded-row space AFTER the editor has moved
  /// its own row controllers; the host must apply the same move to its
  /// canonical value (list order / insertion-ordered map) and emit it.
  /// The editor translates its own row indices into decoded space first
  /// (skipping rows the host's canonical value doesn't contain — empty-key
  /// rows for every host, plus collapsed duplicate-key rows for map hosts —
  /// which the echo-suppressed editor keeps alive) — see `_hostIndexFor`
  /// and [hostIndexing].
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// When non-null, every row except the trailing auto-blank one shows a
  /// duplicate button next to delete. Called with the source row index; the
  /// editor inserts nothing itself — the host inserts the copy below
  /// (params: exact copy; map-backed hosts: a '-copy'-suffixed key) and the
  /// new items arrive as an external change.
  final void Function(int index)? onDuplicate;

  /// Editor-row → host-row index translation semantics for [onReorder],
  /// [onDuplicate] and [onToggleEnabled] — see [KeyValueHostIndexing].
  /// Defaults to [KeyValueHostIndexing.auto], which infers
  /// [KeyValueHostIndexing.list] vs [KeyValueHostIndexing.map] from the
  /// runtime type of [items]; no current host needs to pass this
  /// explicitly (see the wiring note on [KeyValueHostIndexing.auto]).
  final KeyValueHostIndexing hostIndexing;

  @override
  State<KeyValueListEditor<T>> createState() => _KeyValueListEditorState<T>();
}

class _KeyValueListEditorState<T extends Object>
    extends State<KeyValueListEditor<T>> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;
  late List<bool> _rowEnabledFlags;
  T? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.decode(widget.items));
  }

  TextEditingController _newValueController(String value) {
    return widget.variableContext != null
        ? VariableHighlightController(text: value)
        : TextEditingController(text: value);
  }

  void _initControllers(List<(String, String)> rows) {
    _keyControllers = [
      for (final (key, _) in rows) TextEditingController(text: key),
    ];
    _valControllers = [
      for (final (_, value) in rows) _newValueController(value),
    ];
    _rowEnabledFlags = [
      for (var i = 0; i < rows.length; i++) widget.rowEnabled?.call(i) ?? true,
    ];
    _addEmptyRow();
  }

  void _addEmptyRow() {
    _keyControllers.add(TextEditingController());
    _valControllers.add(_newValueController(''));
    _rowEnabledFlags.add(true);
  }

  @override
  void didUpdateWidget(KeyValueListEditor<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lastEmitted = _lastEmitted;
    if (lastEmitted != null && widget.equals(widget.items, lastEmitted)) {
      return;
    }
    if (widget.equals(widget.items, oldWidget.items) &&
        _sameDecodedOrder(widget.items, oldWidget.items)) {
      return;
    }
    // Genuine external change: rebuild from canonical items — but first
    // snapshot editor-only (cleared-key) rows, which canonical items have
    // already dropped, and reinsert them after the rebuild. See the file
    // header's "keyless-row reconcile" gotcha.
    final editorOnlyRows = _snapshotEditorOnlyRows();
    _disposeControllers();
    _initControllers(widget.decode(widget.items));
    _restoreEditorOnlyRows(editorOnlyRows);
    _lastEmitted = null;
  }

  /// Snapshots rows that exist only in this editor — empty key text,
  /// excluding the trailing auto-blank row — as plain data (position, value
  /// TEXT, enabled flag). Deliberately not the controller instances: those
  /// are disposed by [_disposeControllers], so reusing them would be a
  /// use-after-dispose.
  List<({int position, String valueText, bool enabled})>
  _snapshotEditorOnlyRows() {
    final trailingBlankIndex = _keyControllers.length - 1;
    return [
      for (var i = 0; i < trailingBlankIndex; i++)
        if (_keyControllers[i].text.isEmpty)
          (
            position: i,
            valueText: _valControllers[i].text,
            enabled: _rowEnabledFlags[i],
          ),
    ];
  }

  /// Reinserts snapshotted editor-only rows (see [_snapshotEditorOnlyRows])
  /// with equivalent FRESH controllers at their clamped remembered
  /// positions, always before the trailing auto-blank row. Ascending
  /// snapshot order keeps multiple keyless rows in their original relative
  /// order. Runs after [_initControllers], so [_rowEnabledFlags] seeded in
  /// decoded space stays aligned — inserting into all three lists shifts
  /// them identically.
  void _restoreEditorOnlyRows(
    List<({int position, String valueText, bool enabled})> rows,
  ) {
    for (final row in rows) {
      final insertAt = row.position.clamp(0, _keyControllers.length - 1);
      _keyControllers.insert(insertAt, TextEditingController());
      _valControllers.insert(insertAt, _newValueController(row.valueText));
      _rowEnabledFlags.insert(insertAt, row.enabled);
    }
  }

  /// Stricter than `widget.equals`: true only when [a] and [b] decode to
  /// exactly the same rows in the exact same order. Layered on top of (never
  /// replacing) `widget.equals` so a genuine reorder is never missed even
  /// when the caller's own `equals` is order-insensitive (map-backed hosts —
  /// headers/env vars — pass a plain `MapEquality`, which by design doesn't
  /// care about key order). A second line of defense alongside the file
  /// header's "enabled-subsequence pre-move" — the two mechanisms agree by
  /// construction.
  bool _sameDecodedOrder(T a, T b) {
    final rowsA = widget.decode(a);
    final rowsB = widget.decode(b);
    if (rowsA.length != rowsB.length) return false;
    for (var i = 0; i < rowsA.length; i++) {
      if (rowsA[i] != rowsB[i]) return false;
    }
    return true;
  }

  void _disposeControllers() {
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _emit() {
    final rows = [
      for (int i = 0; i < _keyControllers.length; i++)
        (_keyControllers[i].text, _valControllers[i].text),
    ];
    final value = widget.encode(rows);
    _lastEmitted = value;
    widget.onChanged(value);
  }

  void _toggleSecret(int index) {
    final secrets = widget.secretKeys;
    if (secrets == null) return;
    final key = _keyControllers[index].text.trim();
    if (key.isEmpty) return;
    final next = Set<String>.of(secrets);
    next.contains(key) ? next.remove(key) : next.add(key);
    widget.onSecretKeysChanged?.call(next);
  }

  /// Whether host-index translation should use map semantics — explicit via
  /// [KeyValueListEditor.hostIndexing], or inferred from the runtime type of
  /// [KeyValueListEditor.items] under [KeyValueHostIndexing.auto].
  bool get _useMapHostIndexing => switch (widget.hostIndexing) {
    KeyValueHostIndexing.list => false,
    KeyValueHostIndexing.map => true,
    KeyValueHostIndexing.auto => widget.items is Map<Object?, Object?>,
  };

  /// How many canonical (host) rows the first [endExclusive] editor rows
  /// produce, derived through the host's own codec: encode the prefix, count
  /// the decoded result. For an insertion-ordered map host this is exactly
  /// the number of distinct canonical keys in the prefix — first-occurrence
  /// collapse and key canonicalization (env trims) both come from the real
  /// encode, not a re-implementation. Only meaningful when
  /// [_useMapHostIndexing] (map encodes are pure row functions; see
  /// [KeyValueHostIndexing.map]).
  int _canonicalPrefixCount(int endExclusive) {
    final prefix = [
      for (var i = 0; i < endExclusive; i++)
        (_keyControllers[i].text, _valControllers[i].text),
    ];
    return widget.decode(widget.encode(prefix)).length;
  }

  /// Translates an editor row index into the host's decoded-row space by
  /// skipping rows the host's canonical value does not contain. Echo
  /// suppression deliberately keeps such rows alive here (so clearing an
  /// interior key doesn't eat the row mid-edit) — after a clear, raw editor
  /// indices sit one past the host's for everything below it, and
  /// index-based host ops (reorder / duplicate / params' toggle) would hit
  /// the WRONG row. List hosts skip empty-key rows only (every host's
  /// encode drops those); map hosts additionally collapse duplicate /
  /// canonically-equal keys, counted via [_canonicalPrefixCount] — see
  /// [KeyValueHostIndexing].
  int _hostIndexFor(int editorIndex) {
    if (_useMapHostIndexing) return _canonicalPrefixCount(editorIndex);
    var count = 0;
    for (var i = 0; i < editorIndex; i++) {
      if (_keyControllers[i].text.isNotEmpty) count++;
    }
    return count;
  }

  /// Whether the editor row at [editorIndex] has a canonical counterpart the
  /// host can operate on. List hosts: any non-empty key. Map hosts: the row
  /// must grow the canonical prefix count — i.e. be encode-visible AND the
  /// first occurrence of its canonical key; a collapsed duplicate (or, for
  /// env, whitespace-only key) row exists only in this editor, exactly like
  /// a keyless row, so reorder/duplicate sourced from it must not reach the
  /// host (the index would point at some OTHER row's entry).
  bool _rowCountsInHost(int editorIndex) {
    if (_useMapHostIndexing) {
      return _canonicalPrefixCount(editorIndex + 1) >
          _canonicalPrefixCount(editorIndex);
    }
    return _keyControllers[editorIndex].text.isNotEmpty;
  }

  void _toggleEnabled(int index) {
    final next = !_rowEnabledFlags[index];
    setState(() => _rowEnabledFlags[index] = next);
    // An empty-key row exists only in this editor — there is no canonical
    // row for the host to toggle.
    if (_keyControllers[index].text.isEmpty) return;
    widget.onToggleEnabled?.call(
      _hostIndexFor(index),
      _keyControllers[index].text,
      _valControllers[index].text,
      next,
    );
  }

  /// Handles a drop from the ReorderableListView. Wired to `onReorderItem`
  /// (not the deprecated `onReorder`), which already reports `newIndex` in
  /// post-removal space — no manual decrement needed. Clamps/excludes around
  /// the trailing auto-blank row defensively, then locally reflects the move
  /// (see [_repositionWithinEnabledRows]) before reporting it to the host —
  /// see the file header's "enabled-subsequence pre-move" gotcha for why this
  /// is scoped to the enabled rows only rather than a flat splice.
  void _handleReorder(int oldIndex, int newIndex) {
    final host = widget.onReorder;
    if (host == null) return;
    final blankIndex = _keyControllers.length - 1;
    if (oldIndex < 0 || oldIndex >= blankIndex) return;
    var target = newIndex;
    if (target >= blankIndex) target = blankIndex - 1;
    if (target < 0) target = 0;
    if (target == oldIndex) return;
    // Translate into decoded space BEFORE the local pre-move mutates the
    // controller lists (see _hostIndexFor). hostNew counts over the
    // post-removal sequence — the same space the host applies newIndex in.
    final draggedCountsInHost = _rowCountsInHost(oldIndex);
    final hostOld = _hostIndexFor(oldIndex);
    // `target` indexes the POST-removal editor list; its first `target`
    // entries are original rows [0, target) for a backward drag, and
    // original rows [0, target] minus the dragged row for a forward one.
    // (Map hosts: when the dragged row shares its canonical key with a row
    // it crossed, this prefix arithmetic can undercount by one — such a
    // drag is canonically meaningless anyway and degrades to hostNew ==
    // hostOld, i.e. no host call.)
    final hostNew = oldIndex < target
        ? _hostIndexFor(target + 1) - (draggedCountsInHost ? 1 : 0)
        : _hostIndexFor(target);
    _repositionWithinEnabledRows(oldIndex, target, blankIndex);
    // A dragged row without a canonical counterpart (keyless, or a map
    // host's collapsed duplicate — see _rowCountsInHost), or a drag that
    // only crossed such rows, has nothing for the host to move — the local
    // pre-move above already matches what the host's decoded rows echo.
    if (!draggedCountsInHost || hostNew == hostOld) return;
    host(hostOld, hostNew);
  }

  /// Locally reflects a reorder, but ONLY within the enabled-row
  /// subsequence — disabled (e.g. parked) rows stay pinned at their
  /// absolute slot, exactly mirroring hosts that virtually exclude disabled
  /// rows from the reorder space (params' parked rows ride outside the URL
  /// sequence; see `ParamsTabView.reorder`). When the enabled sequence's
  /// relative order doesn't actually change — a drag that crosses only
  /// disabled rows — nothing moves locally either, so a no-op host
  /// round-trip (or one a caller's own `equals`/`buildWhen` treats as
  /// unchanged) never diverges from canonical order. The trailing auto-blank
  /// row (always "enabled") is deliberately excluded via [blankIndex] so it
  /// can never be pulled into the reshuffle. A disabled row can't itself be
  /// the drag source (its handle is gated away in `build()`), so
  /// `_rowEnabledFlags[oldIndex]` is always true in practice; guarded
  /// defensively anyway.
  void _repositionWithinEnabledRows(int oldIndex, int target, int blankIndex) {
    if (!_rowEnabledFlags[oldIndex]) return;
    final dataFlags = _rowEnabledFlags.sublist(0, blankIndex);
    final oldEnabledIndex = dataFlags.take(oldIndex).where((e) => e).length;
    final flagsAfterRemoval = [...dataFlags]..removeAt(oldIndex);
    final newEnabledIndex = flagsAfterRemoval
        .take(target)
        .where((e) => e)
        .length;
    if (newEnabledIndex == oldEnabledIndex) return;
    setState(() {
      final enabledIndices = [
        for (var i = 0; i < blankIndex; i++)
          if (dataFlags[i]) i,
      ];
      final movedKey = _keyControllers[oldIndex];
      final movedVal = _valControllers[oldIndex];
      final splicedKeys = [for (final i in enabledIndices) _keyControllers[i]]
        ..remove(movedKey);
      final splicedVals = [for (final i in enabledIndices) _valControllers[i]]
        ..remove(movedVal);
      final insertAt = newEnabledIndex.clamp(0, splicedKeys.length);
      splicedKeys.insert(insertAt, movedKey);
      splicedVals.insert(insertAt, movedVal);
      for (final (slot, i) in enabledIndices.indexed) {
        _keyControllers[i] = splicedKeys[slot];
        _valControllers[i] = splicedVals[slot];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final onDuplicate = widget.onDuplicate;

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      // onReorder is deprecated in this Flutter version (superseded by
      // onReorderItem, which reports newIndex already adjusted for the
      // removed slot) — see _handleReorder's doc comment.
      onReorderItem: _handleReorder,
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        final secrets = widget.secretKeys;
        // Compare trimmed — secretKeys is stored trimmed (matches _toggleSecret
        // and the env editor's trimming encode), so an untrimmed compare would
        // mis-flag a key with surrounding whitespace.
        final keyText = _keyControllers[index].text.trim();
        final isTrailingBlankRow = index == _keyControllers.length - 1;

        final showToggles =
            widget.rowEnabled != null && widget.onToggleEnabled != null;

        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          rowIndex: index,
          showToggleColumn: showToggles,
          // The trailing auto-blank row never shows a checkbox.
          showCheckbox: showToggles && !isTrailingBlankRow,
          isRowEnabled: _rowEnabledFlags[index],
          onToggleEnabled: showToggles ? () => _toggleEnabled(index) : null,
          readOnlyWhenDisabled: widget.disabledRowsReadOnly,
          fieldPrefix: widget.fieldPrefix,
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          showSecretToggle: secrets != null,
          isSecret:
              secrets != null &&
              keyText.isNotEmpty &&
              secrets.contains(keyText),
          onToggleSecret: secrets == null ? null : () => _toggleSecret(index),
          variableContext: widget.variableContext,
          // Gate on the TRACKED flags (not widget.rowEnabled, whose indices
          // are decoded-space and drift from editor rows after an interior
          // key is cleared — flags follow rows through every local edit).
          showDragHandle:
              widget.onReorder != null &&
              !isTrailingBlankRow &&
              _rowEnabledFlags[index],
          onDuplicate:
              onDuplicate == null ||
                  isTrailingBlankRow ||
                  !_rowEnabledFlags[index]
              ? null
              : () {
                  // A row without a canonical counterpart (keyless, or a map
                  // host's collapsed duplicate — see _rowCountsInHost) has
                  // nothing to duplicate; translate the rest into decoded
                  // space (_hostIndexFor).
                  if (!_rowCountsInHost(index)) return;
                  onDuplicate(_hostIndexFor(index));
                },
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
              setState(_addEmptyRow);
            }
            _emit();
          },
          onValChanged: (_) => _emit(),
          onDelete: () {
            setState(() {
              _keyControllers.removeAt(index).dispose();
              _valControllers.removeAt(index).dispose();
              _rowEnabledFlags.removeAt(index);
              // Re-add a blank row whenever the list is now empty OR the new
              // last row has a non-empty key — otherwise deleting a trailing
              // blank row (leaving e.g. [a=1]) would strand the editor with
              // no row left to type a new entry into.
              if (_keyControllers.isEmpty ||
                  _keyControllers.last.text.isNotEmpty) {
                _addEmptyRow();
              }
              _emit();
            });
          },
        );
      },
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  const _KeyValueRow({
    required this.keyController,
    required this.valController,
    required this.layout,
    required this.onKeyChanged,
    required this.onValChanged,
    required this.onDelete,
    super.key,
    this.rowIndex = 0,
    this.fieldPrefix,
    this.showSecretToggle = false,
    this.isSecret = false,
    this.onToggleSecret,
    this.variableContext,
    this.showToggleColumn = false,
    this.showCheckbox = false,
    this.isRowEnabled = true,
    this.onToggleEnabled,
    this.readOnlyWhenDisabled = false,
    this.showDragHandle = false,
    this.onDuplicate,
  });
  final bool showToggleColumn;
  final bool showCheckbox;
  final bool isRowEnabled;
  final VoidCallback? onToggleEnabled;
  final bool readOnlyWhenDisabled;
  final bool showDragHandle;
  final VoidCallback? onDuplicate;
  final int rowIndex;
  final String? fieldPrefix;
  final TextEditingController keyController;
  final TextEditingController valController;
  final AppLayout layout;
  final ValueChanged<String> onKeyChanged;
  final ValueChanged<String> onValChanged;
  final VoidCallback onDelete;
  final bool showSecretToggle;
  final bool isSecret;
  final VoidCallback? onToggleSecret;
  final LayeredVariableContext? variableContext;

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  bool _isHovered = false;
  bool _revealed = false;
  final FocusNode _valueFocusNode = FocusNode();

  @override
  void dispose() {
    _valueFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_KeyValueRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset reveal whenever secret status flips so a row re-marked secret
    // always starts obscured instead of inheriting a stale "revealed".
    if (oldWidget.isSecret != widget.isSecret) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhone = context.isPhone;
    final fieldPadding = EdgeInsets.all(widget.layout.isCompact ? 8 : 12);
    final textStyle = TextStyle(
      fontSize: widget.layout.fontSizeNormal,
      fontWeight: context.appTypography.titleWeight,
    );

    final keyField = TextField(
      key: widget.fieldPrefix == null
          ? null
          : ValueKey('${widget.fieldPrefix}_key_${widget.rowIndex}'),
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'KEY',
        isDense: true,
        contentPadding: fieldPadding,
      ),
      controller: widget.keyController,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onKeyChanged,
    );

    // Build the value field decoration once so both the plain path and the
    // VariableTextField path share the exact same decoration.
    final valueDecoration = InputDecoration(
      hintText: 'VALUE',
      isDense: true,
      contentPadding: fieldPadding,
      // Reveal toggle lives in the field so the row layout is unchanged.
      suffixIcon: widget.isSecret
          ? IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _revealed ? Icons.visibility_off : Icons.visibility,
                size: widget.layout.isCompact ? 18 : 20,
              ),
              tooltip: _revealed ? 'Hide value' : 'Reveal value',
              onPressed: () => setState(() => _revealed = !_revealed),
            )
          : null,
    );

    final ctx = widget.variableContext;
    final valController = widget.valController;

    // Use VariableTextField when the context is non-null and the controller
    // is a VariableHighlightController. Secret rows pass a null context (the
    // env editor), so the two paths never combine.
    final Widget valueFieldWithAutocomplete =
        (ctx == null || valController is! VariableHighlightController)
        ? TextField(
            key: widget.fieldPrefix == null
                ? null
                : ValueKey('${widget.fieldPrefix}_val_${widget.rowIndex}'),
            style: textStyle,
            focusNode: _valueFocusNode,
            obscureText: widget.isSecret && !_revealed,
            decoration: valueDecoration,
            controller: valController,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: widget.onValChanged,
          )
        : VariableTextField(
            fieldKey: widget.fieldPrefix == null
                ? null
                : ValueKey('${widget.fieldPrefix}_val_${widget.rowIndex}'),
            variables: ctx,
            controller: valController,
            focusNode: _valueFocusNode,
            onChanged: widget.onValChanged,
            decoration: valueDecoration,
            style: textStyle,
          );

    final enabledToggle = widget.showToggleColumn
        ? SizedBox(
            width: widget.layout.kvToggleSlotWidth,
            child: widget.showCheckbox
                ? Checkbox(
                    key: widget.fieldPrefix == null
                        ? null
                        : ValueKey(
                            '${widget.fieldPrefix}_enabled_${widget.rowIndex}',
                          ),
                    value: widget.isRowEnabled,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) => widget.onToggleEnabled?.call(),
                  )
                : null,
          )
        : null;

    // Disabled rows dim; with readOnlyWhenDisabled they also stop accepting
    // pointer/focus input (checkbox + delete stay live — they sit outside).
    Widget dim(Widget child) => widget.isRowEnabled
        ? child
        : Opacity(opacity: widget.layout.kvDisabledRowOpacity, child: child);
    Widget lockIfReadOnly(Widget child) =>
        widget.isRowEnabled || !widget.readOnlyWhenDisabled
        ? child
        : ExcludeFocus(child: IgnorePointer(child: child));
    final keyCell = dim(lockIfReadOnly(keyField));
    final valueCell = dim(lockIfReadOnly(valueFieldWithAutocomplete));

    final secretButton = widget.showSecretToggle
        ? context.appDecoration.wrapInteractive(
            child: IconButton(
              icon: Icon(
                widget.isSecret ? Icons.lock_outline : Icons.lock_open_outlined,
                size: widget.layout.isCompact ? 20 : 24,
                color: widget.isSecret
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              tooltip: widget.isSecret ? 'Unmark secret' : 'Mark secret',
              onPressed: widget.onToggleSecret,
            ),
          )
        : null;
    final dragHandle = widget.showDragHandle
        ? ReorderableDragStartListener(
            index: widget.rowIndex,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.layout.isCompact ? 2.0 : 4.0,
                ),
                child: Icon(
                  Icons.drag_indicator,
                  size: widget.layout.isCompact ? 18 : 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          )
        : null;
    final duplicateButton = widget.onDuplicate == null
        ? null
        : context.appDecoration.wrapInteractive(
            child: IconButton(
              icon: Icon(
                Icons.content_copy,
                size: widget.layout.isCompact ? 20 : 24,
                color: theme.colorScheme.secondary,
              ),
              tooltip: 'Duplicate row',
              onPressed: widget.onDuplicate,
            ),
          );
    final deleteButton = context.appDecoration.wrapInteractive(
      child: IconButton(
        icon: Icon(
          Icons.delete_outline,
          size: widget.layout.isCompact ? 20 : 24,
          color: theme.colorScheme.error,
        ),
        onPressed: widget.onDelete,
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: widget.layout.isCompact ? 8.0 : 12.0),
        padding: EdgeInsets.symmetric(
          horizontal: isPhone ? 8 : 4,
          vertical: isPhone ? 8 : 2,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? theme.hoverColor
              : (isPhone ? theme.colorScheme.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          border: Border.all(
            color: isPhone
                ? theme.dividerColor.withValues(alpha: 0.6)
                : (_isHovered
                      ? theme.dividerColor.withValues(alpha: 0.5)
                      : Colors.transparent),
            width: widget.layout.borderThin,
          ),
        ),
        child: isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ?dragHandle,
                      ?enabledToggle,
                      Expanded(child: keyCell),
                      ?secretButton,
                      ?duplicateButton,
                      deleteButton,
                    ],
                  ),
                  SizedBox(height: widget.layout.tabSpacing),
                  valueCell,
                ],
              )
            : Row(
                children: [
                  ?dragHandle,
                  ?enabledToggle,
                  Expanded(child: keyCell),
                  SizedBox(width: widget.layout.isCompact ? 8 : 12),
                  Expanded(child: valueCell),
                  SizedBox(width: widget.layout.isCompact ? 4 : 8),
                  ?secretButton,
                  ?duplicateButton,
                  deleteButton,
                ],
              ),
      ),
    );
  }
}

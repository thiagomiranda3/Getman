// Prepares large editor documents off the UI isolate. Revisions reject stale
// completions after newer model values, user edits or disposal. The controller
// and its undo history always stay on the UI isolate.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

/// Applies a user-requested replacement (e.g. Beautify) with normal undo and
/// edit notifications, only if its originating editor/text is still current.
Future<bool> replaceCodeText(
  CodeLineEditingController controller,
  String text, {
  required bool Function() isCurrent,
}) async {
  final lines = text.length < 64 * 1024
      ? text.codeLines
      : await text.codeLinesAsync;
  if (!isCurrent()) return false;
  controller.runRevocableOp(() {
    controller.value = CodeLineEditingValue(codeLines: lines);
  });
  return true;
}

class CodeTextLoader {
  CodeTextLoader(this.controller, this.onReady, {this.prepare = _prepare})
    : _lines = controller.codeLines;

  final CodeLineEditingController controller;
  final VoidCallback onReady;
  final Future<CodeLines> Function(String) prepare;
  CodeLines _lines;
  String? _text;
  int _revision = 0;
  bool _disposed = false;
  bool _applying = false;
  bool loading = false;
  Object? error;

  static Future<CodeLines> _prepare(String text) => text.codeLinesAsync;

  void load(String text) {
    if (_disposed || text == _text) return;
    _text = text;
    error = null;
    final revision = ++_revision;
    if (text.length < 64 * 1024) {
      _apply(text.codeLines);
    } else {
      loading = true;
      unawaited(_load(text, revision));
    }
  }

  Future<void> _load(String text, int revision) async {
    try {
      final lines = await prepare(text);
      if (_disposed || revision != _revision) return;
      _apply(lines);
    } on Object catch (failure) {
      if (_disposed || revision != _revision) return;
      error = failure;
      loading = false;
    }
    if (!_disposed && revision == _revision) onReady();
  }

  void _apply(CodeLines lines) {
    _applying = true;
    try {
      controller.runRevocableOp(() {
        controller.value = CodeLineEditingValue(codeLines: lines);
      });
      _lines = controller.codeLines;
      loading = false;
    } finally {
      _applying = false;
    }
  }

  /// Selection-only notifications do not join all document lines again.
  String? takeEdit() {
    if (_applying || identical(_lines, controller.codeLines)) return null;
    _lines = controller.codeLines;
    _revision++;
    loading = false;
    error = null;
    return _text = controller.text;
  }

  void dispose() {
    _disposed = true;
    _revision++;
  }
}

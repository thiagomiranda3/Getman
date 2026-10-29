// Debounced advisory JSON diagnostics around a request-body editor. Small
// initial documents validate synchronously; large ones use compute. Revision
// guards discard obsolete async results on edits, controller swaps or disposal.
// Selection-only notifications never reparse. This widget never gates sending.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/debouncer.dart';
import 'package:getman/features/tabs/domain/logic/json_body_validation.dart';
import 'package:re_editor/re_editor.dart';

/// Wraps a bounded editor with a clickable JSON syntax advisory.
class BodyJsonValidation extends StatefulWidget {
  const BodyJsonValidation({
    required this.controller,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final CodeLineEditingController controller;
  final Widget child;
  final bool enabled;

  @override
  State<BodyJsonValidation> createState() => _BodyJsonValidationState();
}

class _BodyJsonValidationState extends State<BodyJsonValidation> {
  static const _backgroundThreshold = 100000;
  final _debouncer = Debouncer(duration: const Duration(milliseconds: 250));
  late CodeLines _lastLines;
  late String _lastText;
  JsonBodyValidationError? _error;
  var _revision = 0;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _lastLines = widget.controller.codeLines;
    _lastText = widget.controller.text;
    widget.controller.addListener(_onChanged);
    _initializeValidation();
  }

  void _initializeValidation() {
    _revision++;
    _debouncer.cancel();
    _error = null;
    if (!widget.enabled) return;
    if (_lastText.length < _backgroundThreshold) {
      _error = validateJsonBody(_lastText);
    } else {
      unawaited(_validate(_lastText, _revision));
    }
  }

  @override
  void didUpdateWidget(BodyJsonValidation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      _attach();
    } else if (oldWidget.enabled != widget.enabled) {
      _initializeValidation();
    }
  }

  void _onChanged() {
    final lines = widget.controller.codeLines;
    if (identical(lines, _lastLines)) return;
    _lastLines = lines;
    final text = widget.controller.text;
    if (text == _lastText) return;
    _lastText = text;
    _revision++;
    _debouncer.cancel();
    if (_error != null) setState(() => _error = null);
    if (!widget.enabled) return;
    final revision = _revision;
    _debouncer.run(() => unawaited(_validate(text, revision)));
  }

  Future<void> _validate(String text, int revision) async {
    final error = text.length < _backgroundThreshold
        ? validateJsonBody(text)
        : await compute(validateJsonBody, text);
    if (!mounted || revision != _revision || !widget.enabled) return;
    if (error != _error) setState(() => _error = error);
  }

  void _goToError(JsonBodyValidationError error) {
    final controller = widget.controller;
    var position = controller.lineIndex2Index(error.line - 1);
    while (position.chunkIndex != -1) {
      controller.expandChunk(position.index);
      position = controller.lineIndex2Index(error.line - 1);
    }
    controller
      ..selection = CodeLineSelection.collapsed(
        index: position.index,
        offset: error.column - 1,
      )
      ..makeCursorVisible();
  }

  @override
  void dispose() {
    _revision++;
    widget.controller.removeListener(_onChanged);
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final layout = context.appLayout;
    final color = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: widget.child),
        if (error != null)
          InkWell(
            key: const ValueKey('body-json-validation-error'),
            onTap: () => _goToError(error),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: layout.inputPadding,
                vertical: layout.inputPaddingVertical,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: color,
                    size: layout.smallIconSize,
                  ),
                  SizedBox(width: layout.tabSpacing),
                  Expanded(
                    child: Text(
                      'JSON syntax: ${error.message} '
                      '(line ${error.line}, column ${error.column})',
                      style: TextStyle(
                        color: color,
                        fontSize: layout.fontSizeSmall,
                        fontWeight: context.appTypography.bodyWeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

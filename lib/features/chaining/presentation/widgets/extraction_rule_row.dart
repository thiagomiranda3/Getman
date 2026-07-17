// One editable extraction-rule row (kind dropdown + expression/target-
// variable fields) inside the RULES tab. Owns its controllers (keyed by
// id) so editing keeps focus; reports edits up via onChanged.

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/presentation/widgets/rule_card.dart';

class ExtractionRuleRow extends StatefulWidget {
  const ExtractionRuleRow({
    required this.index,
    required this.rule,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });
  final int index;
  final ExtractionRule rule;
  final ValueChanged<ExtractionRule> onChanged;
  final VoidCallback onDelete;

  @override
  State<ExtractionRuleRow> createState() => _ExtractionRuleRowState();
}

class _ExtractionRuleRowState extends State<ExtractionRuleRow> {
  static const Map<ExtractionKind, String> _kindLabels = {
    ExtractionKind.jsonPath: 'JSON PATH',
    ExtractionKind.header: 'HEADER',
    ExtractionKind.regex: 'REGEX',
  };

  late ExtractionKind _kind = widget.rule.kind;
  late bool _enabled = widget.rule.enabled;
  late final TextEditingController _expression = TextEditingController(
    text: widget.rule.expression,
  );
  late final TextEditingController _target = TextEditingController(
    text: widget.rule.targetVariable,
  );

  @override
  void dispose() {
    _expression.dispose();
    _target.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(
    ExtractionRule(
      id: widget.rule.id,
      kind: _kind,
      expression: _expression.text,
      targetVariable: _target.text,
      enabled: _enabled,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return RuleCard(
      enabled: _enabled,
      onToggle: (v) {
        setState(() => _enabled = v);
        _emit();
      },
      onDelete: widget.onDelete,
      children: [
        DropdownButton<ExtractionKind>(
          key: ValueKey('extraction_kind_${widget.index}'),
          value: _kind,
          isDense: true,
          items: [
            for (final k in ExtractionKind.values)
              DropdownMenuItem(value: k, child: Text(_kindLabels[k]!)),
          ],
          onChanged: (k) {
            if (k == null) return;
            setState(() => _kind = k);
            _emit();
          },
        ),
        SizedBox(height: layout.tabSpacing),
        _field(
          context,
          _expression,
          _kind == ExtractionKind.header ? 'HEADER NAME' : 'EXPRESSION',
          ValueKey('extraction_expr_${widget.index}'),
        ),
        SizedBox(height: layout.tabSpacing),
        _field(
          context,
          _target,
          'TARGET VARIABLE',
          ValueKey('extraction_target_${widget.index}'),
        ),
      ],
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController c,
    String hint,
    Key fieldKey,
  ) {
    final layout = context.appLayout;
    return TextField(
      key: fieldKey,
      controller: c,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(
        fontSize: layout.fontSizeNormal,
        fontWeight: context.appTypography.titleWeight,
      ),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: EdgeInsets.all(layout.isCompact ? 8 : 12),
      ),
      onChanged: (_) => _emit(),
    );
  }
}

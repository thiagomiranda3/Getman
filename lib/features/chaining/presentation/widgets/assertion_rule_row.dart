import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/presentation/widgets/rule_card.dart';

// ---------------------------------------------------------------------------
// Assertion row
// ---------------------------------------------------------------------------

class AssertionRuleRow extends StatefulWidget {
  const AssertionRuleRow({
    required this.index,
    required this.assertion,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });
  final int index;
  final Assertion assertion;
  final ValueChanged<Assertion> onChanged;
  final VoidCallback onDelete;

  @override
  State<AssertionRuleRow> createState() => _AssertionRuleRowState();
}

class _AssertionRuleRowState extends State<AssertionRuleRow> {
  static const Map<AssertionTarget, String> _targetLabels = {
    AssertionTarget.statusCode: 'STATUS',
    AssertionTarget.responseTime: 'TIME (ms)',
    AssertionTarget.bodyJsonPath: 'BODY (JSONPath)',
    AssertionTarget.header: 'HEADER',
  };
  static const Map<AssertionComparator, String> _compLabels = {
    AssertionComparator.equals: '=',
    AssertionComparator.notEquals: '≠',
    AssertionComparator.contains: 'contains',
    AssertionComparator.lessThan: '<',
    AssertionComparator.greaterThan: '>',
    AssertionComparator.inRange: 'in range',
    AssertionComparator.exists: 'exists',
  };

  late AssertionTarget _target = widget.assertion.target;
  late AssertionComparator _comparator = widget.assertion.comparator;
  late bool _enabled = widget.assertion.enabled;
  late final TextEditingController _path = TextEditingController(
    text: widget.assertion.path,
  );
  late final TextEditingController _expected = TextEditingController(
    text: widget.assertion.expected,
  );

  bool get _needsPath =>
      _target == AssertionTarget.bodyJsonPath ||
      _target == AssertionTarget.header;
  bool get _needsExpected => _comparator != AssertionComparator.exists;

  @override
  void dispose() {
    _path.dispose();
    _expected.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(
    Assertion(
      id: widget.assertion.id,
      target: _target,
      comparator: _comparator,
      path: _path.text,
      expected: _expected.text,
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
        Wrap(
          spacing: layout.tabSpacing,
          runSpacing: layout.tabSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<AssertionTarget>(
              key: ValueKey('assertion_target_${widget.index}'),
              value: _target,
              isDense: true,
              items: [
                for (final t in AssertionTarget.values)
                  DropdownMenuItem(value: t, child: Text(_targetLabels[t]!)),
              ],
              onChanged: (t) {
                if (t == null) return;
                setState(() => _target = t);
                _emit();
              },
            ),
            DropdownButton<AssertionComparator>(
              key: ValueKey('assertion_comp_${widget.index}'),
              value: _comparator,
              isDense: true,
              items: [
                for (final c in AssertionComparator.values)
                  DropdownMenuItem(value: c, child: Text(_compLabels[c]!)),
              ],
              onChanged: (c) {
                if (c == null) return;
                setState(() => _comparator = c);
                _emit();
              },
            ),
          ],
        ),
        if (_needsPath) ...[
          SizedBox(height: layout.tabSpacing),
          _field(
            context,
            _path,
            _target == AssertionTarget.header ? 'HEADER NAME' : 'JSONPath',
            ValueKey('assertion_path_${widget.index}'),
          ),
        ],
        if (_needsExpected) ...[
          SizedBox(height: layout.tabSpacing),
          _field(
            context,
            _expected,
            _comparator == AssertionComparator.inRange
                ? 'EXPECTED (lo-hi)'
                : 'EXPECTED',
            ValueKey('assertion_expected_${widget.index}'),
          ),
        ],
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

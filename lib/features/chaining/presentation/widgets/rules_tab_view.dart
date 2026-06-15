import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:uuid/uuid.dart';

/// RULES tab: no-code extraction rules + assertions for the active request.
/// Loads/saves through [RulesBloc] keyed by the request's config id. Mount with
/// a per-tab key so switching tabs reloads the right rules.
class RulesTabView extends StatefulWidget {
  const RulesTabView({required this.tabId, super.key});
  final String tabId;

  @override
  State<RulesTabView> createState() => _RulesTabViewState();
}

class _RulesTabViewState extends State<RulesTabView> {
  static const _uuid = Uuid();
  late final String _configId;
  late RequestRulesEntity _draft;
  RequestRulesEntity? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _configId =
        context.read<TabsBloc>().state.tabs.byId(widget.tabId)?.config.id ?? '';
    _draft = RequestRulesEntity(configId: _configId);
    context.read<RulesBloc>().add(LoadRules(_configId));
  }

  void _emit() {
    _lastEmitted = _draft;
    context.read<RulesBloc>().add(SaveRules(_draft));
  }

  void _updateExtraction(ExtractionRule rule) {
    final list = [
      for (final r in _draft.extractionRules)
        if (r.id == rule.id) rule else r,
    ];
    setState(() => _draft = _draft.copyWith(extractionRules: list));
    _emit();
  }

  void _updateAssertion(Assertion a) {
    final list = [
      for (final x in _draft.assertions)
        if (x.id == a.id) a else x,
    ];
    setState(() => _draft = _draft.copyWith(assertions: list));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocListener<RulesBloc, RulesState>(
      listenWhen: (prev, next) => next.rules?.configId == _configId,
      listener: (context, state) {
        final loaded = state.rules;
        if (loaded == null) return;
        if (_lastEmitted != null && loaded == _lastEmitted) return; // our echo
        setState(() => _draft = loaded);
      },
      child: ListView(
        padding: EdgeInsets.all(layout.pagePadding),
        children: [
          const _Header(label: 'EXTRACT VARIABLES'),
          for (final rule in _draft.extractionRules)
            _ExtractionRuleRow(
              key: ValueKey('x_${rule.id}'),
              rule: rule,
              onChanged: _updateExtraction,
              onDelete: () {
                setState(
                  () => _draft = _draft.copyWith(
                    extractionRules: _draft.extractionRules
                        .where((r) => r.id != rule.id)
                        .toList(),
                  ),
                );
                _emit();
              },
            ),
          _AddButton(
            label: 'ADD EXTRACTION',
            onTap: () {
              setState(
                () => _draft = _draft.copyWith(
                  extractionRules: [
                    ..._draft.extractionRules,
                    ExtractionRule(id: _uuid.v4()),
                  ],
                ),
              );
              _emit();
            },
          ),
          SizedBox(height: layout.sectionSpacing),
          const _Header(label: 'ASSERTIONS'),
          for (final a in _draft.assertions)
            _AssertionRow(
              key: ValueKey('a_${a.id}'),
              assertion: a,
              onChanged: _updateAssertion,
              onDelete: () {
                setState(
                  () => _draft = _draft.copyWith(
                    assertions: _draft.assertions
                        .where((x) => x.id != a.id)
                        .toList(),
                  ),
                );
                _emit();
              },
            ),
          _AddButton(
            label: 'ADD ASSERTION',
            onTap: () {
              setState(
                () => _draft = _draft.copyWith(
                  assertions: [
                    ..._draft.assertions,
                    Assertion(id: _uuid.v4()),
                  ],
                ),
              );
              _emit();
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Text(
        label,
        style: TextStyle(
          fontSize: layout.fontSizeSmall,
          fontWeight: context.appTypography.displayWeight,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add),
        label: Text(label),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extraction rule row — owns its controllers (keyed by id) so editing keeps
// focus; reports edits up via onChanged.
// ---------------------------------------------------------------------------

class _ExtractionRuleRow extends StatefulWidget {
  const _ExtractionRuleRow({
    required this.rule,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });
  final ExtractionRule rule;
  final ValueChanged<ExtractionRule> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ExtractionRuleRow> createState() => _ExtractionRuleRowState();
}

class _ExtractionRuleRowState extends State<_ExtractionRuleRow> {
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
    return _RuleCard(
      enabled: _enabled,
      onToggle: (v) {
        setState(() => _enabled = v);
        _emit();
      },
      onDelete: widget.onDelete,
      children: [
        DropdownButton<ExtractionKind>(
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
        ),
        SizedBox(height: layout.tabSpacing),
        _field(context, _target, 'TARGET VARIABLE'),
      ],
    );
  }

  Widget _field(BuildContext context, TextEditingController c, String hint) {
    final layout = context.appLayout;
    return TextField(
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

// ---------------------------------------------------------------------------
// Assertion row
// ---------------------------------------------------------------------------

class _AssertionRow extends StatefulWidget {
  const _AssertionRow({
    required this.assertion,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });
  final Assertion assertion;
  final ValueChanged<Assertion> onChanged;
  final VoidCallback onDelete;

  @override
  State<_AssertionRow> createState() => _AssertionRowState();
}

class _AssertionRowState extends State<_AssertionRow> {
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
    return _RuleCard(
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
          ),
        ],
      ],
    );
  }

  Widget _field(BuildContext context, TextEditingController c, String hint) {
    final layout = context.appLayout;
    return TextField(
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

/// Shared card chrome for a rule/assertion row: enable toggle + delete.
class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.enabled,
    required this.onToggle,
    required this.onDelete,
    required this.children,
  });
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      margin: EdgeInsets.only(bottom: layout.isCompact ? 8 : 12),
      padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
              SizedBox(width: layout.tabSpacing),
              Column(
                children: [
                  Switch(
                    value: enabled,
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    onChanged: onToggle,
                  ),
                  context.appDecoration.wrapInteractive(
                    child: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                        size: layout.iconSize,
                      ),
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

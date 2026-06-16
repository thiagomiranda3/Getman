import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_state.dart';
import 'package:getman/features/chaining/presentation/widgets/assertion_rule_row.dart';
import 'package:getman/features/chaining/presentation/widgets/extraction_rule_row.dart';
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
          for (final (i, rule) in _draft.extractionRules.indexed)
            ExtractionRuleRow(
              key: ValueKey('x_${rule.id}'),
              index: i,
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
          for (final (i, a) in _draft.assertions.indexed)
            AssertionRuleRow(
              key: ValueKey('a_${a.id}'),
              index: i,
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

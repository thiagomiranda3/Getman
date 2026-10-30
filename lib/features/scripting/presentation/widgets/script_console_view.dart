// Bounded, redacted diagnostics for both JavaScript execution stages.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_diagnostic_redactor.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';

String scriptPhaseLabel(ScriptPhase phase) =>
    phase == ScriptPhase.preRequest ? 'PRE-REQUEST' : 'POST-RESPONSE';

class ScriptConsoleView extends StatelessWidget {
  const ScriptConsoleView({
    required this.result,
    this.tabId,
    this.secretValues = const {},
    super.key,
  });
  final String? tabId;
  final ExecuteRequestResult result;
  final Set<String> secretValues;
  @override
  Widget build(BuildContext context) {
    final redactor = ScriptDiagnosticRedactor(
      secretValues: {...secretValues, ...result.secretValues},
    );
    final outputs = [
      if (result.preRequest != null) result.preRequest!,
      if (result.postResponse != null) result.postResponse!,
    ];
    final errors = {
      ...outputs.map((o) => o.error).nonNulls,
      if (result.error != null) result.error!,
    };
    return ListView(
      padding: EdgeInsets.all(context.appLayout.inputPadding),
      children: [
        if (result.cancelled) const Text('CANCELLED'),
        for (final error in errors)
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: InkWell(
              onTap: tabId == null
                  ? null
                  : () => context.read<RequestSectionIndex>().openScript(
                      tabId: tabId!,
                      postResponse: error.phase == ScriptPhase.postResponse,
                      line: error.line ?? 1,
                      column: error.column ?? 1,
                    ),
              child: Text(
                redactor.redact(
                  '${scriptPhaseLabel(error.phase)}: '
                  '${error.kind.name}'
                  '${error.line == null ? '' : ' at line ${error.line}'}'
                  '${error.column == null ? '' : ', column ${error.column}'}'
                  ': ${error.message}',
                ),
              ),
            ),
          ),
        for (final output in outputs)
          for (final log in output.logs)
            SelectableText(
              redactor.redact(
                '${scriptPhaseLabel(log.phase)} '
                '[${log.level}] ${log.message}',
              ),
            ),
        if (errors.isEmpty && outputs.every((o) => o.logs.isEmpty))
          const Text('No console output'),
      ],
    );
  }
}

class ScriptTestsView extends StatelessWidget {
  const ScriptTestsView({
    required this.result,
    this.secretValues = const {},
    super.key,
  });
  final ExecuteRequestResult result;
  final Set<String> secretValues;
  @override
  Widget build(BuildContext context) {
    final tests = [
      ...?result.preRequest?.tests,
      ...?result.postResponse?.tests,
    ];
    final redact = ScriptDiagnosticRedactor(
      secretValues: {...secretValues, ...result.secretValues},
    );
    return ListView(
      padding: EdgeInsets.all(context.appLayout.inputPadding),
      children: [
        Text('${tests.where((t) => t.passed).length}/${tests.length} passed'),
        for (final test in tests)
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              key: ValueKey('${test.phase.name}:${test.id}'),
              title: Text(
                redact.redact('${scriptPhaseLabel(test.phase)}: ${test.name}'),
              ),
              leading: Icon(test.passed ? Icons.check : Icons.close),
              subtitle: test.message == null
                  ? null
                  : Text(redact.redact(test.message!)),
            ),
          ),
      ],
    );
  }
}

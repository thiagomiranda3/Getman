// Script diagnostics stay useful without an HTTP response and mask secrets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/entities/script_test_result.dart';
import 'package:getman/features/scripting/presentation/widgets/script_console_view.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';

void main() {
  testWidgets('tests count repeated names separately across stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: ScriptTestsView(
            result: ExecuteRequestResult(
              preRequest: ScriptOutput(
                tests: const [
                  ScriptTestResult(
                    id: 'a',
                    name: 'same',
                    phase: ScriptPhase.preRequest,
                    passed: true,
                  ),
                ],
              ),
              postResponse: ScriptOutput(
                tests: const [
                  ScriptTestResult(
                    id: 'b',
                    name: 'same',
                    phase: ScriptPhase.postResponse,
                    passed: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('1/2 passed'), findsOneWidget);
    expect(find.text('PRE-REQUEST: same'), findsOneWidget);
    expect(find.text('POST-RESPONSE: same'), findsOneWidget);
  });
  testWidgets(
    'pre-request error without HTTP masks secrets and shows position',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: const Scaffold(
            body: ScriptConsoleView(
              result: ExecuteRequestResult(
                error: ScriptError(
                  kind: ScriptErrorKind.syntax,
                  phase: ScriptPhase.preRequest,
                  message: 'unexpected secret-token',
                  line: 2,
                ),
              ),
              secretValues: {'secret-token'},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('PRE-REQUEST'), findsWidgets);
      expect(find.textContaining('line 2'), findsOneWidget);
      expect(find.textContaining('secret-token'), findsNothing);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/compare_target_picker.dart';

HttpResponseEntity _resp(int status) => HttpResponseEntity(
  statusCode: status,
  body: '{}',
  headers: const {},
  durationMs: 1,
);

Future<CompareTarget?> _open(
  WidgetTester tester, {
  required List<CompareTarget> examples,
  required List<CompareTarget> history,
}) async {
  CompareTarget? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(kBrutalistThemeId)(
        Brightness.light,
        isCompact: false,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<CompareTarget>(
                context: context,
                builder: (_) =>
                    CompareTargetPicker(examples: examples, history: history),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('renders both labeled sections', (tester) async {
    await _open(
      tester,
      examples: [
        CompareTarget(
          id: 'e1',
          source: CompareTargetSource.example,
          label: '200 · 14:03',
          subtitle: 'captured today',
          response: _resp(200),
        ),
      ],
      history: [
        CompareTarget(
          id: 'h1',
          source: CompareTargetSource.history,
          label: 'GET /users · 200',
          subtitle: 'a minute ago',
          response: _resp(200),
        ),
      ],
    );
    expect(find.text('SAVED EXAMPLES'), findsOneWidget);
    expect(find.text('RECENT (this request)'), findsOneWidget);
    expect(find.text('200 · 14:03'), findsOneWidget);
    expect(find.text('GET /users · 200'), findsOneWidget);
  });

  testWidgets('an empty section shows None', (tester) async {
    await _open(
      tester,
      examples: const [],
      history: [
        CompareTarget(
          id: 'h1',
          source: CompareTargetSource.history,
          label: 'GET /users · 200',
          subtitle: 'a minute ago',
          response: _resp(200),
        ),
      ],
    );
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('tapping a row pops that target', (tester) async {
    final picked = CompareTarget(
      id: 'e1',
      source: CompareTargetSource.example,
      label: '200 · 14:03',
      subtitle: 'captured today',
      response: _resp(200),
    );
    CompareTarget? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme(kBrutalistThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<CompareTarget>(
                  context: context,
                  builder: (_) => CompareTargetPicker(
                    examples: [picked],
                    history: const [],
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('200 · 14:03'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.id, 'e1');
  });
}

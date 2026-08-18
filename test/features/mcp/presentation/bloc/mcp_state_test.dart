// McpTabSession.copyWith sentinel semantics: lastResult/errorMessage keep
// their value when OMITTED and clear when explicitly passed null — the old
// always-replace behavior silently wiped the displayed result on every
// unrelated copyWith (e.g. re-tapping the selected tool chip).

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';

void main() {
  const result = McpToolResult(
    isError: false,
    textBlocks: ['42'],
    rawBlocks: [],
  );
  const session = McpTabSession(
    status: McpConnectionStatus.connected,
    selectedTool: 'add',
    lastResult: result,
    errorMessage: 'boom',
  );

  group('McpTabSession.copyWith sentinel', () {
    test('omitting lastResult/errorMessage keeps the current values', () {
      final copy = session.copyWith(calling: true);
      expect(copy.lastResult, result);
      expect(copy.errorMessage, 'boom');
      expect(copy.calling, isTrue);
    });

    test('passing null explicitly clears lastResult/errorMessage', () {
      final copy = session.copyWith(lastResult: null, errorMessage: null);
      expect(copy.lastResult, isNull);
      expect(copy.errorMessage, isNull);
    });

    test('passing new values replaces them', () {
      const other = McpToolResult(
        isError: true,
        textBlocks: ['nope'],
        rawBlocks: [],
      );
      final copy = session.copyWith(lastResult: other, errorMessage: 'later');
      expect(copy.lastResult, other);
      expect(copy.errorMessage, 'later');
    });
  });
}

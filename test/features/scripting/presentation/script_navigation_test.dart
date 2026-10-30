// Diagnostic locations select scripts even when the section is already open.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';

void main() {
  test('diagnostic selection records target tab, phase and line', () {
    final index = RequestSectionIndex();
    addTearDown(index.dispose);
    index.openScript(tabId: 'tab', postResponse: true, line: 2, column: 3);
    expect(index.value, 4);
    expect(index.scriptTabId, 'tab');
    expect(index.scriptPostResponse, isTrue);
    expect(index.scriptLine, 2);
    expect(index.scriptColumn, 3);
  });
}

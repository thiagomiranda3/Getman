import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

void main() {
  test('AmbientSignals holds its listenables + pulse', () {
    final pointer = ValueNotifier<Offset>(Offset.zero);
    final pulse = WorkspacePulseController();
    final s = AmbientSignals(
      pointer: pointer,
      pulse: pulse,
      isDark: true,
    );
    expect(s.pointer, same(pointer));
    expect(s.pulse, same(pulse));
    expect(s.isDark, isTrue);
    pointer.dispose();
    pulse.dispose();
  });
}

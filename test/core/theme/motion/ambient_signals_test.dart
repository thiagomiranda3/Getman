import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

void main() {
  test('AmbientImpulse value equality', () {
    const a = AmbientImpulse(position: Offset(0.2, 0.3), bornAtMs: 1000);
    const b = AmbientImpulse(position: Offset(0.2, 0.3), bornAtMs: 1000);
    const c = AmbientImpulse(position: Offset(0.2, 0.3), bornAtMs: 2000);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });

  test('AmbientSignals holds its listenables + pulse', () {
    final pointer = ValueNotifier<Offset>(Offset.zero);
    final impulses = ValueNotifier<List<AmbientImpulse>>(const []);
    final pulse = WorkspacePulseController();
    final s = AmbientSignals(
      pointer: pointer,
      impulses: impulses,
      pulse: pulse,
      isDark: true,
    );
    expect(s.pointer, same(pointer));
    expect(s.impulses, same(impulses));
    expect(s.pulse, same(pulse));
    expect(s.isDark, isTrue);
    pointer.dispose();
    impulses.dispose();
    pulse.dispose();
  });
}

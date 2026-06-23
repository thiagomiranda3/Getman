import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

void main() {
  test('starts with zero idle', () {
    final c = WorkspacePulseController();
    expect(c.idleFactor, 0);
    c.dispose();
  });

  test('tick raises idleFactor toward 1', () {
    final c = WorkspacePulseController()..tick();
    expect(c.idleFactor, greaterThan(0));
    // Enough ticks saturates idle at 1.
    for (var i = 0; i < 60; i++) {
      c.tick();
    }
    expect(c.idleFactor, 1);
    c.dispose();
  });

  test('touch resets idle to 0', () {
    final c = WorkspacePulseController();
    for (var i = 0; i < 40; i++) {
      c.tick();
    }
    expect(c.idleFactor, 1);
    c.touch();
    expect(c.idleFactor, 0);
    c.dispose();
  });

  test('touch is a no-op when idle is already 0', () {
    final c = WorkspacePulseController();
    var notified = 0;
    c
      ..addListener(() => notified++)
      ..touch(); // idle == 0, should not notify
    expect(notified, 0);
    c.dispose();
  });

  test('tick notifies listeners when idleFactor changes', () {
    final c = WorkspacePulseController();
    var notified = 0;
    c
      ..addListener(() => notified++)
      ..tick();
    expect(notified, greaterThan(0));
    c.dispose();
  });

  test(
    'timer lifecycle: starts on addListener, stops on last removeListener',
    () {
      final c = WorkspacePulseController();
      expect(c.debugHasListeners, isFalse);
      void listener() {}
      c.addListener(listener);
      expect(c.debugHasListeners, isTrue);
      c.removeListener(listener);
      expect(c.debugHasListeners, isFalse);
      c.dispose();
    },
  );
}

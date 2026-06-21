import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

void main() {
  test('starts idle-free and inactive', () {
    final c = WorkspacePulseController();
    expect(c.activityLevel, 0);
    expect(c.idleFactor, 0);
    c.dispose();
  });

  test('bump raises activity (clamped to 1) and resets idle', () {
    final c = WorkspacePulseController();
    // Build up some idle first.
    for (var i = 0; i < 40; i++) {
      c.tick();
    }
    expect(c.idleFactor, 1);
    c.bump();
    expect(c.activityLevel, greaterThan(0));
    expect(c.idleFactor, 0);
    // Many bumps clamp at 1.
    for (var i = 0; i < 20; i++) {
      c.bump();
    }
    expect(c.activityLevel, 1);
    c.dispose();
  });

  test('tick decays activity toward 0 and raises idleFactor', () {
    final c = WorkspacePulseController()..bump();
    final afterBump = c.activityLevel;
    c.tick();
    expect(c.activityLevel, lessThan(afterBump));
    // Enough ticks fully decays activity and saturates idle.
    for (var i = 0; i < 60; i++) {
      c.tick();
    }
    expect(c.activityLevel, 0);
    expect(c.idleFactor, 1);
    c.dispose();
  });

  test('touch resets idle without changing activity', () {
    final c = WorkspacePulseController();
    for (var i = 0; i < 40; i++) {
      c.tick();
    }
    expect(c.idleFactor, 1);
    c.touch();
    expect(c.idleFactor, 0);
    expect(c.activityLevel, 0);
    c.dispose();
  });

  test('notifies listeners on bump', () {
    final c = WorkspacePulseController();
    var notified = 0;
    c
      ..addListener(() => notified++)
      ..bump();
    expect(notified, greaterThan(0));
    c.dispose();
  });
}

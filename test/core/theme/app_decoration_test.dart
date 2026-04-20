import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

BoxDecoration _noopPanel(BuildContext ctx, {Color? color, double? borderWidth, double? offset, BorderRadius? borderRadius}) =>
    const BoxDecoration();
BoxDecoration _noopTab(BuildContext ctx, {required bool active, required bool hovered}) => const BoxDecoration();
Widget _noopWrap({required Widget child, VoidCallback? onTap, double? scaleDown}) => child;

void main() {
  group('AppDecoration', () {
    const a = AppDecoration(
      panelBox: _noopPanel,
      tabShape: _noopTab,
      wrapInteractive: _noopWrap,
    );

    test('copyWith swaps provided closures and keeps others', () {
      BoxDecoration newPanel(BuildContext ctx, {Color? color, double? borderWidth, double? offset, BorderRadius? borderRadius}) =>
          const BoxDecoration(color: Colors.red);
      final copy = a.copyWith(panelBox: newPanel);
      expect(identical(copy.panelBox, newPanel), isTrue);
      expect(identical(copy.tabShape, a.tabShape), isTrue);
      expect(identical(copy.wrapInteractive, a.wrapInteractive), isTrue);
    });

    test('lerp returns this regardless of target', () {
      final b = a.copyWith();
      expect(a.lerp(b, 0.5), a);
      expect(a.lerp(null, 0.5), a);
    });
  });
}

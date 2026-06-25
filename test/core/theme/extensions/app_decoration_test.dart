import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_decoration.dart';

AppDecoration _base() => AppDecoration(
  panelBox: (context, {color, borderWidth, offset, borderRadius}) =>
      const BoxDecoration(),
  tabShape: (context, {required active, required hovered, required isFirst}) =>
      const BoxDecoration(),
  wrapInteractive: ({required child, onTap, scaleDown}) => child,
  scaffoldBackground: (context, {required child}) => child,
);

void main() {
  group('AppDecoration.dialogSurface', () {
    test('defaults to null', () {
      expect(_base().dialogSurface, isNull);
    });

    test('copyWith carries a provided dialogSurface', () {
      Widget builder(
        BuildContext context, {
        required Widget child,
        required BorderRadius borderRadius,
      }) => child;
      final updated = _base().copyWith(dialogSurface: builder);
      expect(updated.dialogSurface, same(builder));
    });

    test('copyWith without dialogSurface keeps the existing one', () {
      Widget builder(
        BuildContext context, {
        required Widget child,
        required BorderRadius borderRadius,
      }) => child;
      final withHook = _base().copyWith(dialogSurface: builder);
      final unchanged = withHook.copyWith();
      expect(unchanged.dialogSurface, same(builder));
    });
  });
}

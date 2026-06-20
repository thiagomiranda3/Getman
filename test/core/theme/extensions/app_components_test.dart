import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';

void main() {
  test('AppComponents.lerp returns this (closures do not interpolate)', () {
    final c = AppComponents(
      surface: (context, {required child, title, code, accent = false}) =>
          child,
      methodBadge: (context, {required method, small = false}) =>
          const SizedBox(),
      statusBadge: (context, {required statusCode}) => const SizedBox(),
      metric:
          (
            context, {
            required label,
            required value,
            unit,
            delta,
          }) => const SizedBox(),
      toggle:
          (
            context, {
            required value,
            required onChanged,
            label,
          }) => const SizedBox(),
      logView: (context, {required lines, title, controller}) =>
          const SizedBox(),
      dataRow:
          (
            context, {
            required label,
            required value,
            highlight = false,
          }) => const SizedBox(),
      select: (context, spec) => const SizedBox(),
      pendingIndicator: (context, {label}) => const SizedBox(),
      statusBanner: (context, {required state, required message}) =>
          const SizedBox(),
    );
    expect(identical(c.lerp(null, 0.5), c), isTrue);
    expect(c.copyWith().surface, equals(c.surface));
  });

  test('neutral types construct', () {
    const line = AppLogLine(text: 'hi', kind: AppLogLineKind.open);
    expect(line.kind, AppLogLineKind.open);
    final spec = AppSelectSpec(
      items: const [AppSelectItem(label: 'A')],
      selectedIndex: 0,
      onSelected: (_) {},
    );
    expect(spec.items.single.label, 'A');
    expect(AppBannerState.values.length, 4);
  });
}

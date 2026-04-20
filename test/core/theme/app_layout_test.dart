import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  group('AppLayout', () {
    test('normal and compact constants differ on pagePadding', () {
      expect(AppLayout.normal.pagePadding, isNot(AppLayout.compact.pagePadding));
    });

    test('includes fontSizeCode and fontSizeSubtitle', () {
      expect(AppLayout.normal.fontSizeCode, 13.0);
      expect(AppLayout.compact.fontSizeCode, 12.0);
      expect(AppLayout.normal.fontSizeSubtitle, 18.0);
      expect(AppLayout.compact.fontSizeSubtitle, 14.0);
    });

    test('copyWith preserves non-overridden fields', () {
      final copy = AppLayout.normal.copyWith(pagePadding: 99.0);
      expect(copy.pagePadding, 99.0);
      expect(copy.sectionSpacing, AppLayout.normal.sectionSpacing);
      expect(copy.fontSizeCode, AppLayout.normal.fontSizeCode);
    });

    test('lerp interpolates numerics and snaps ints/bools to other', () {
      final mid = AppLayout.normal.lerp(AppLayout.compact, 0.5);
      expect(
        mid.pagePadding,
        closeTo((AppLayout.normal.pagePadding + AppLayout.compact.pagePadding) / 2, 0.001),
      );
      expect(mid.isCompact, AppLayout.compact.isCompact);
      expect(mid.tabTitleMaxLength, AppLayout.compact.tabTitleMaxLength);
    });

    test('lerp with a different type returns this', () {
      final result = AppLayout.normal.lerp(null, 0.5);
      expect(result, AppLayout.normal);
    });
  });
}

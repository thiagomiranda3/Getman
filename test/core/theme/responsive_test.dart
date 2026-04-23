import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/responsive.dart';

void main() {
  group('layoutModeForWidth', () {
    test('compactPhone at and below the 500 px threshold', () {
      expect(layoutModeForWidth(0), LayoutMode.compactPhone);
      expect(layoutModeForWidth(320), LayoutMode.compactPhone);
      expect(layoutModeForWidth(500), LayoutMode.compactPhone);
    });

    test('phone between 500 and 700', () {
      expect(layoutModeForWidth(500.1), LayoutMode.phone);
      expect(layoutModeForWidth(640), LayoutMode.phone);
      expect(layoutModeForWidth(700), LayoutMode.phone);
    });

    test('tablet between 700 and 900', () {
      expect(layoutModeForWidth(700.1), LayoutMode.tablet);
      expect(layoutModeForWidth(800), LayoutMode.tablet);
      expect(layoutModeForWidth(900), LayoutMode.tablet);
    });

    test('desktop above 900', () {
      expect(layoutModeForWidth(900.1), LayoutMode.desktop);
      expect(layoutModeForWidth(1440), LayoutMode.desktop);
      expect(layoutModeForWidth(3840), LayoutMode.desktop);
    });
  });

  group('ResponsiveBuildContext', () {
    Future<void> pumpAt(WidgetTester tester, double width, void Function(BuildContext) onBuild) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                onBuild(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    testWidgets('desktop width reports no mobile affordances', (tester) async {
      late BuildContext ctx;
      await pumpAt(tester, 1440, (c) => ctx = c);
      expect(ctx.layoutMode, LayoutMode.desktop);
      expect(ctx.isPhone, isFalse);
      expect(ctx.useDrawerNav, isFalse);
      expect(ctx.useUnifiedRequestTabs, isFalse);
      expect(ctx.useTabSwitcher, isFalse);
      expect(ctx.isDialogFullscreen, isFalse);
      expect(ctx.touchTargetMin, 28.0);
    });

    testWidgets('tablet width turns on drawer-nav only', (tester) async {
      late BuildContext ctx;
      await pumpAt(tester, 800, (c) => ctx = c);
      expect(ctx.layoutMode, LayoutMode.tablet);
      expect(ctx.useDrawerNav, isTrue);
      expect(ctx.useUnifiedRequestTabs, isFalse);
      expect(ctx.useTabSwitcher, isFalse);
      expect(ctx.isPhone, isFalse);
    });

    testWidgets('phone width turns on drawer + unified tabs + fullscreen dialogs', (tester) async {
      late BuildContext ctx;
      await pumpAt(tester, 640, (c) => ctx = c);
      expect(ctx.layoutMode, LayoutMode.phone);
      expect(ctx.isPhone, isTrue);
      expect(ctx.useDrawerNav, isTrue);
      expect(ctx.useUnifiedRequestTabs, isTrue);
      expect(ctx.isDialogFullscreen, isTrue);
      expect(ctx.useTabSwitcher, isFalse);
      expect(ctx.touchTargetMin, 44.0);
    });

    testWidgets('compact-phone width additionally turns on the tab switcher', (tester) async {
      late BuildContext ctx;
      await pumpAt(tester, 375, (c) => ctx = c);
      expect(ctx.layoutMode, LayoutMode.compactPhone);
      expect(ctx.useTabSwitcher, isTrue);
      expect(ctx.useUnifiedRequestTabs, isTrue);
      expect(ctx.useDrawerNav, isTrue);
    });
  });
}

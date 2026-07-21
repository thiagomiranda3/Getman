import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/updates/presentation/widgets/update_download_dialog.dart';

void main() {
  Widget host() {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => UpdateDownloadDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the blocking download dialog with a spinner', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();

    expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('cannot be dismissed by barrier tap or Escape', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();

    // Barrier tap (top-left corner is outside the dialog card).
    await t.tapAt(const Offset(5, 5));
    await t.pump();
    expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);

    // Escape key.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);
  });
}

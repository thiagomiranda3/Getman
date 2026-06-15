import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/in_memory_cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/cookies/presentation/widgets/cookie_manager_dialog.dart';

class _FakePersistence implements CookiePersistence {
  @override
  List<NetworkCookie> loadAll() => const [];
  @override
  Future<void> upsert(NetworkCookie cookie) async {}
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> clearAll() async {}
}

void main() {
  late InMemoryCookieStore store;

  setUp(() {
    store = InMemoryCookieStore(persistence: _FakePersistence(), now: () => 1000);
  });

  Future<void> pumpAndOpen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: RepositoryProvider<CookieStore>.value(
          value: store,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CookieManagerDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists stored cookies', (tester) async {
    store.storeFromSetCookie(Uri.parse('https://api.dev/'), 'sid=abc; Path=/');
    store.storeFromSetCookie(Uri.parse('https://api.dev/'), 'theme=dark; Path=/');

    await pumpAndOpen(tester);

    expect(find.textContaining('sid = abc'), findsOneWidget);
    expect(find.textContaining('theme = dark'), findsOneWidget);
    expect(find.textContaining('API.DEV'), findsOneWidget);
  });

  testWidgets('shows the empty state when the jar is empty', (tester) async {
    await pumpAndOpen(tester);
    expect(find.text('NO COOKIES STORED'), findsOneWidget);
  });

  testWidgets('deleting a cookie removes it from the store after confirming', (tester) async {
    store.storeFromSetCookie(Uri.parse('https://api.dev/'), 'sid=abc; Path=/');
    store.storeFromSetCookie(Uri.parse('https://api.dev/'), 'theme=dark; Path=/');

    await pumpAndOpen(tester);
    expect(store.all(), hasLength(2));

    await tester.tap(find.byTooltip('Delete cookie').first);
    await tester.pumpAndSettle();
    // ConfirmDialog is up; confirm.
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    expect(store.all(), hasLength(1));
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test('fires the action once after the quiet window', () {
      fakeAsync((async) {
        final debouncer = Debouncer(
          duration: const Duration(milliseconds: 200),
        );
        var calls = 0;
        debouncer.run(() => calls++);

        async.elapse(const Duration(milliseconds: 199));
        expect(calls, 0, reason: 'must not fire before the window elapses');

        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);
        debouncer.dispose();
      });
    });

    test(
      'collapses a burst of calls into a single run with the latest action',
      () {
        fakeAsync((async) {
          final debouncer = Debouncer(
            duration: const Duration(milliseconds: 200),
          );
          final fired = <int>[];
          for (var i = 0; i < 5; i++) {
            debouncer.run(() => fired.add(i));
            async.elapse(
              const Duration(milliseconds: 50),
            ); // each call resets the timer
          }
          async.elapse(const Duration(milliseconds: 200));

          expect(fired, [
            4,
          ], reason: 'only the last scheduled action runs, once');
          debouncer.dispose();
        });
      },
    );

    test('dispose cancels a pending action', () {
      fakeAsync((async) {
        final debouncer = Debouncer(
          duration: const Duration(milliseconds: 200),
        );
        var calls = 0;
        debouncer
          ..run(() => calls++)
          ..dispose();

        async.elapse(const Duration(milliseconds: 500));
        expect(calls, 0);
      });
    });
  });
}

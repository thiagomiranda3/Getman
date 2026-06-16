import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/bloc/request_manager.dart';

void main() {
  group('RequestManager', () {
    late RequestManager manager;

    setUp(() {
      manager = RequestManager();
    });

    test('start registers a handle that is not yet cancelled', () {
      final handle = manager.start('tab-1');
      expect(handle.isCancelled, isFalse);
    });

    test('cancel marks the handle as cancelled and forgets it', () {
      final handle = manager.start('tab-1');
      manager.cancel('tab-1');
      expect(handle.isCancelled, isTrue);
    });

    test('cancelling an unknown tab id is a no-op', () {
      expect(() => manager.cancel('no-such-tab'), returnsNormally);
    });

    test('cancelling an already-removed tab id is a no-op', () {
      manager
        ..start('tab-1')
        ..finish('tab-1');
      expect(() => manager.cancel('tab-1'), returnsNormally);
    });

    test('finish forgets a handle without cancelling it', () {
      final handle = manager.start('tab-1');
      manager.finish('tab-1');
      // The handle was not cancelled — finish only removes the mapping.
      expect(handle.isCancelled, isFalse);
      // A subsequent cancel for that tabId is a no-op (no longer tracked).
      expect(() => manager.cancel('tab-1'), returnsNormally);
    });

    test('cancelAndFinish cancels and removes the handle', () {
      final handle = manager.start('tab-1');
      manager.cancelAndFinish('tab-1');
      expect(handle.isCancelled, isTrue);
      // After cancelAndFinish the handle is no longer tracked; cancelling again
      // is safe.
      expect(() => manager.cancel('tab-1'), returnsNormally);
    });

    test('cancelAll cancels every registered handle', () {
      final h1 = manager.start('tab-1');
      final h2 = manager.start('tab-2');
      final h3 = manager.start('tab-3');

      manager.cancelAll();

      expect(h1.isCancelled, isTrue);
      expect(h2.isCancelled, isTrue);
      expect(h3.isCancelled, isTrue);
    });

    test('cancelAll is a no-op when no handles are registered', () {
      expect(() => manager.cancelAll(), returnsNormally);
    });

    test('cancelAll does not double-cancel an already-cancelled handle', () {
      final handle = manager.start('tab-1');
      manager.cancel('tab-1'); // first cancel
      // cancelAll should not throw even though the handle is already cancelled.
      expect(() => manager.cancelAll(), returnsNormally);
      expect(handle.isCancelled, isTrue);
    });

    test('cancel with custom reason propagates via isCancelled', () {
      final handle = manager.start('tab-1');
      manager.cancel('tab-1', reason: 'custom reason');
      expect(handle.isCancelled, isTrue);
    });
  });
}

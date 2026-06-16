import 'package:getman/core/network/cancel_handle.dart';

/// Maps an in-flight `tabId` to its cancel handle so the bloc can cancel a
/// specific tab's request (or all of them on close). Extracted from TabsBloc so
/// the cancellation bookkeeping is unit-testable in isolation.
class RequestManager {
  final Map<String, NetworkCancelHandle> _handles = {};

  NetworkCancelHandle start(String tabId) {
    final handle = NetworkCancelHandle();
    _handles[tabId] = handle;
    return handle;
  }

  void finish(String tabId) => _handles.remove(tabId);

  void cancel(String tabId, {String reason = 'User cancelled request'}) {
    final handle = _handles[tabId];
    if (handle != null && !handle.isCancelled) {
      handle.cancel(reason);
    }
  }

  /// Cancel the in-flight request (if any) and drop the handle.
  void cancelAndFinish(String tabId) {
    cancel(tabId);
    finish(tabId);
  }

  void cancelAll() {
    for (final handle in _handles.values) {
      if (!handle.isCancelled) handle.cancel('Bloc closed');
    }
    _handles.clear();
  }
}

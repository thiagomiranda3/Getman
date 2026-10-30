// Per-tab request-cancellation bookkeeping, extracted out of TabsBloc.
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';

/// Maps an in-flight `tabId` to its cancel handle so the bloc can cancel a
/// specific tab's request (or all of them on close). Extracted from TabsBloc so
/// the cancellation bookkeeping is unit-testable in isolation.
class RequestManager {
  final Map<String, NetworkCancelHandle> _handles = {};
  final Map<String, ScriptCancellation> _scripts = {};
  ScriptCancellation cancellationFor(String tabId) => _scripts[tabId]!;

  NetworkCancelHandle start(String tabId) {
    cancelAndFinish(tabId);
    final handle = NetworkCancelHandle();
    _scripts[tabId] = ScriptCancellation();
    _handles[tabId] = handle;
    return handle;
  }

  /// A send owns the tab until its post-response rules finish too. A newer
  /// send replaces the handle, invalidating any older async completion.
  bool isCurrent(String tabId, NetworkCancelHandle handle) =>
      identical(_handles[tabId], handle);

  void finish(String tabId, {NetworkCancelHandle? handle}) {
    if (handle == null || isCurrent(tabId, handle)) {
      _handles.remove(tabId);
      _scripts.remove(tabId);
    }
  }

  void cancel(String tabId, {String reason = 'User cancelled request'}) {
    _scripts[tabId]?.cancel();
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
    for (final cancellation in _scripts.values) {
      cancellation.cancel();
    }
    _scripts.clear();
    for (final handle in _handles.values) {
      if (!handle.isCancelled) handle.cancel('Bloc closed');
    }
    _handles.clear();
  }
}

import 'package:getman/core/network/network_service.dart' show NetworkService;

/// Pure-Dart cancellation handle carried across the send pipeline.
///
/// Holds **no** networking dependency: [NetworkService] binds it to a Dio
/// `CancelToken` at request time via [bindCancel], so the domain layer can pass
/// a cancel handle around without importing dio/flutter. Cancelling before the
/// request dispatches is safe — a late [bindCancel] fires immediately so the
/// in-flight request is still torn down.
class NetworkCancelHandle {
  bool _cancelled = false;
  String _reason = 'Cancelled';
  void Function(String reason)? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel([String reason = 'Cancelled']) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    _onCancel?.call(reason);
  }

  /// Bridges this handle to a concrete canceller (e.g. Dio's
  /// `CancelToken.cancel`). If the handle was already cancelled, [onCancel]
  /// fires immediately with the original reason.
  void bindCancel(void Function(String reason) onCancel) {
    _onCancel = onCancel;
    if (_cancelled) onCancel(_reason);
  }
}

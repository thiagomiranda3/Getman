// Double-click on the tab strip's EMPTY area opens a new tab (Postman
// parity): TabStripDoubleClickDetector wraps the strip's scrollable and
// detects two quick primary-button downs itself on a raw Listener, and each
// chip is wrapped in TabChipHitTarget so clicks that land on a chip never
// count as "empty area".
//
// Gotchas: this deliberately does NOT use GestureDetector.onDoubleTap — an
// ancestor double-tap recognizer holds the gesture arena for ~300ms on every
// click, which would delay every chip's onTap (tab switching would lag).
// A Listener only observes, so chip taps stay instant; chip discrimination
// is a subtree hit test for the TabChipHitMarker MetaData instead.
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Hit-test marker carried by [TabChipHitTarget]'s [MetaData] so
/// [TabStripDoubleClickDetector] can tell "on a chip" from "empty strip".
class TabChipHitMarker {
  const TabChipHitMarker();
}

/// Wraps one tab chip so pointer downs on it are excluded from the strip's
/// double-click-to-new-tab detection.
class TabChipHitTarget extends StatelessWidget {
  const TabChipHitTarget({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MetaData(metaData: const TabChipHitMarker(), child: child);
}

/// Detects a double primary-click on the tab strip's empty area (anywhere in
/// [child] that is not covered by a [TabChipHitTarget]) and calls [onNewTab] —
/// the same action as the "+" button.
class TabStripDoubleClickDetector extends StatefulWidget {
  const TabStripDoubleClickDetector({
    required this.onNewTab,
    required this.child,
    super.key,
  });
  final VoidCallback onNewTab;
  final Widget child;

  @override
  State<TabStripDoubleClickDetector> createState() =>
      _TabStripDoubleClickDetectorState();
}

class _TabStripDoubleClickDetectorState
    extends State<TabStripDoubleClickDetector> {
  Duration? _lastDownTime;
  Offset? _lastDownPosition;

  void _reset() {
    _lastDownTime = null;
    _lastDownPosition = null;
  }

  /// Whether [globalPosition] lands on a tab chip: hit-tests only this
  /// detector's subtree and looks for the [TabChipHitMarker] MetaData.
  bool _hitsTabChip(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(globalPosition));
    return result.path.any(
      (entry) =>
          entry.target is RenderMetaData &&
          (entry.target as RenderMetaData).metaData is TabChipHitMarker,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || _hitsTabChip(event.position)) {
      _reset();
      return;
    }
    final lastTime = _lastDownTime;
    final lastPosition = _lastDownPosition;
    if (lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= kDoubleTapTimeout &&
        (event.position - lastPosition).distance <= kDoubleTapSlop) {
      // Consume the pair so a triple-click doesn't open a second tab.
      _reset();
      widget.onNewTab();
      return;
    }
    _lastDownTime = event.timeStamp;
    _lastDownPosition = event.position;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(onPointerDown: _onPointerDown, child: widget.child);
  }
}

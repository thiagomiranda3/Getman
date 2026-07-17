// Drag payload for a tab dragged out of the tab strip (e.g. onto
// PanelSelector); see the class doc for why it isn't a bare String.

/// Drag payload for a tab being dragged out of the tab strip (e.g. onto the
/// panel selector to move it into another panel).
///
/// A dedicated type — rather than a bare `String` — keeps this drag distinct
/// from a collection-tree node drag (`NodeDragData`): both used to be typed
/// `Draggable<String>`/`DragTarget<String>`, so a tab dragged over the
/// collections tree (or a node dragged over the panel selector) would
/// silently highlight and get "accepted" by the wrong target, dispatching a
/// no-op bloc event. Typing each drag distinctly makes foreign targets reject
/// it at the type level instead.
class TabDragData {
  const TabDragData(this.tabId);

  final String tabId;
}

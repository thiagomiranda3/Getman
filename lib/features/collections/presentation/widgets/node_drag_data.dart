/// Drag payload for a collection-tree node (folder or request) being
/// reordered/moved within the tree.
///
/// A dedicated type — rather than a bare `String` — keeps this drag distinct
/// from a tab-strip drag (`TabDragData` in the tabs feature): both used to be
/// typed `Draggable<String>`/`DragTarget<String>`, so a tab dragged over the
/// collections tree (or a node dragged over the panel selector) would
/// silently highlight and get "accepted" by the wrong target, dispatching a
/// no-op bloc event. Typing each drag distinctly makes foreign targets reject
/// it at the type level instead.
class NodeDragData {
  const NodeDragData(this.nodeId);

  final String nodeId;
}

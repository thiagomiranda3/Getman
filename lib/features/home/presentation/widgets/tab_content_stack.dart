import 'package:flutter/material.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/screens/request_view.dart';
import 'package:re_editor/re_editor.dart'
    as re_editor
    show CodeLineEditingController;

/// Maximum number of live [RequestView] instances kept in memory.
/// Each live view holds two [re_editor.CodeLineEditingController]s and their
/// render state. Values beyond this cap are evicted with LRU policy.
const int kMaxLiveTabViews = 5;

/// Keeps up to [kMaxLiveTabViews] [RequestView]s alive in a [Stack]/[Offstage]
/// so that switching tabs does not rebuild the editor tree from scratch.
///
/// Reconciliation runs synchronously on every `build` call:
///  1. Ids belonging to closed tabs are evicted.
///  2. The active tab is added to the live set when not already present.
///  3. The oldest non-active tab is evicted when the live set exceeds the cap.
///
/// A [FocusScopeNode] is created per live id so that switching back to a tab
/// restores focus to the same descendant widget that last had it. A
/// post-frame callback requests focus into the newly-active scope whenever the
/// active id changes, keeping keyboard shortcuts wired inside [RequestView]
/// (SaveRequestIntent, BeautifyJsonIntent) reachable without relying on
/// autofocus from a fresh mount.
///
/// [childBuilder] is exposed for testing — production code leaves it null so
/// the default [RequestView] builder is used.
class TabContentStack extends StatefulWidget {
  const TabContentStack({
    required this.tabs,
    required this.activeIndex,
    super.key,
    this.childBuilder,
  });
  final List<HttpRequestTabEntity> tabs;
  final int activeIndex;

  /// Overrides the child builder. Provide a lightweight stand-in in tests to
  /// avoid setting up the full BLoC/provider tree that [RequestView] needs.
  final Widget Function(String tabId)? childBuilder;

  @override
  State<TabContentStack> createState() => _TabContentStackState();
}

class _TabContentStackState extends State<TabContentStack> {
  /// Ordered list of ids that currently have a live child widget.
  /// Append-only (except evictions/removals) so that stable keys survive
  /// position shifts.
  final List<String> _liveIds = [];

  /// Monotonic counter used to assign LRU timestamps.
  int _useCounter = 0;

  /// Last-use timestamp per live id.
  final Map<String, int> _lastUsed = {};

  /// One FocusScopeNode per live id, created on first use. Nodes are disposed
  /// in a post-frame callback after eviction (not inline during build) so that
  /// the framework can cleanly detach them before disposal.
  final Map<String, FocusScopeNode> _scopeNodes = {};

  /// Nodes collected during [_reconcile] that need deferred disposal, keyed by
  /// the tab id they were evicted from. Keying by id lets [_scopeFor] recover
  /// the same node when the same id is re-added before the post-frame flush
  /// (e.g. a tab closed and reopened within the same frame).
  final Map<String, FocusScopeNode> _pendingDispose = {};

  /// The active tab id from the previous build; used to detect changes that
  /// require a focus-steal post-frame callback.
  String? _lastActiveId;

  @override
  void dispose() {
    for (final node in _scopeNodes.values) {
      node.dispose();
    }
    for (final node in _pendingDispose.values) {
      node.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Reconciliation helpers
  // ---------------------------------------------------------------------------

  /// Returns a [FocusScopeNode] for [id], creating one if this is the first
  /// time this id is seen. If the id was recently evicted but the post-frame
  /// flush has not yet run, the pending node is recovered to avoid creating a
  /// duplicate that would leak its predecessor.
  FocusScopeNode _scopeFor(String id) {
    final pending = _pendingDispose.remove(id);
    if (pending != null) {
      _scopeNodes[id] = pending;
      return pending;
    }
    return _scopeNodes.putIfAbsent(id, FocusScopeNode.new);
  }

  /// Removes bookkeeping for [id] and queues its [FocusScopeNode] for deferred
  /// disposal (via a post-frame callback) so we never dispose a node while it
  /// is still referenced by a [FocusScope] widget in the current frame.
  void _evict(String id) {
    _liveIds.remove(id);
    _lastUsed.remove(id);
    final node = _scopeNodes.remove(id);
    if (node != null) {
      _pendingDispose[id] = node;
    }
  }

  /// Disposes all nodes that were queued by [_evict] since the last flush.
  void _flushPendingDispose() {
    for (final node in _pendingDispose.values) {
      node.dispose();
    }
    _pendingDispose.clear();
  }

  /// Runs full reconciliation and returns the current active tab id, or null
  /// when `widget.tabs` is empty.
  ///
  /// Called once per `build` invocation (synchronous, no setState). Evicted
  /// [FocusScopeNode]s are collected for deferred disposal via a post-frame
  /// callback.
  String? _reconcile() {
    final currentIds = {for (final t in widget.tabs) t.tabId};

    // 1. Remove ids of closed tabs. Materialize with toList() first so _evict
    // can mutate _liveIds without a concurrent-modification error.
    _liveIds.where((id) => !currentIds.contains(id)).toList().forEach(_evict);

    if (widget.tabs.isEmpty) return null;

    // Guard: caller guarantees a valid index, but be defensive.
    final safeIndex = widget.activeIndex.clamp(0, widget.tabs.length - 1);
    final activeId = widget.tabs[safeIndex].tabId;

    // 2. Add the active id to the live set if it is not already present.
    if (!_liveIds.contains(activeId)) {
      _liveIds.add(activeId);
    }

    // 3. Stamp the active id as most-recently used.
    _lastUsed[activeId] = ++_useCounter;

    // 4. Evict the LRU non-active tab when over the cap.
    while (_liveIds.length > kMaxLiveTabViews) {
      // Find the non-active id with the smallest last-use timestamp.
      String? lruId;
      var lruStamp = _useCounter + 1;
      for (final id in _liveIds) {
        if (id == activeId) continue;
        final stamp = _lastUsed[id] ?? 0;
        if (stamp < lruStamp) {
          lruStamp = stamp;
          lruId = id;
        }
      }
      if (lruId == null) break; // Shouldn't happen, but don't loop forever.
      _evict(lruId);
    }

    return activeId;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final activeId = _reconcile();

    if (activeId == null) {
      return const SizedBox.shrink();
    }

    // Schedule a single post-frame callback to (a) flush evicted FocusScopeNode
    // disposals after the framework has detached them, and (b) request focus
    // into the newly-active scope so keyboard shortcuts inside RequestView
    // remain reachable without relying on autofocus from a fresh mount.
    if (_pendingDispose.isNotEmpty || activeId != _lastActiveId) {
      final focusTarget = activeId != _lastActiveId ? activeId : null;
      if (activeId != _lastActiveId) _lastActiveId = activeId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _flushPendingDispose();
        if (focusTarget != null) _scopeNodes[focusTarget]?.requestFocus();
      });
    }

    final builder =
        widget.childBuilder ??
        (String id) => RequestView(key: ValueKey('view_$id'), tabId: id);

    // Use Stack + Offstage rather than IndexedStack. IndexedStack wraps
    // children in anonymous Offstage nodes internally, so Flutter cannot match
    // keyed children across rebuilds when the children list changes — the
    // entire set gets disposed and remounted. With an explicit Stack whose
    // direct children carry the ValueKey, Flutter's element reconciliation
    // matches by key and keeps existing subtrees alive across evictions and
    // list reorders.
    // Offstage children skip paint and hit-testing but still participate in
    // ancestor relayout — every resize or splitter drag lays out all live views
    // (up to kMaxLiveTabViews). This is an intentional trade-off; the cap keeps
    // the cost bounded.
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final id in _liveIds)
          Offstage(
            key: ValueKey('offstage_$id'),
            offstage: id != activeId,
            child: ExcludeFocus(
              excluding: id != activeId,
              child: FocusScope(
                node: _scopeFor(id),
                child: TickerMode(
                  enabled: id == activeId,
                  child: builder(id),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

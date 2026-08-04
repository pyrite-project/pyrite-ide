/// Load state of a tree node's children.
enum ChildrenState {
  /// Children are present (or the node is a leaf).
  loaded,

  /// Children exist but have not been fetched yet; expanding triggers
  /// `requestChildren`.
  unloaded,

  /// A fetch is in flight.
  loading,

  /// The last fetch failed; the row renders an error affordance.
  error,
}

/// One node in the logical tree.
///
/// [label] is mutable so a single-node relabel never touches the index — the
/// spec requires a label update not to rebuild the list.
class TreeNodeModel {
  TreeNodeModel({
    required this.id,
    required this.label,
    this.parentId,
    this.icon,
    this.hasChildren = false,
    this.childrenState = ChildrenState.loaded,
    this.data = const {},
  });

  final String id;
  String label;
  final String? parentId;
  String? icon;
  bool hasChildren;
  ChildrenState childrenState;
  Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'parentId': ?parentId,
    'icon': ?icon,
    'hasChildren': hasChildren,
    'childrenState': childrenState.name,
  };
}

/// A tree with an incrementally-maintained visible-row index.
///
/// Holds the logical structure — including nodes whose children are not loaded —
/// so a plugin can describe 100k logical nodes while the widget layer only ever
/// materializes the visible window.
///
/// Expanding or collapsing splices just the affected span of [visibleNodeIds]
/// rather than re-flattening the tree, so cost is proportional to the rows that
/// actually appear or disappear.
class TreeIndex {
  /// Every known node, keyed by id.
  final Map<String, TreeNodeModel> nodeById = {};

  /// Child ids per parent; the null key holds the roots.
  final Map<String?, List<String>> childrenByParent = {};

  /// Ids whose children are currently shown.
  final Set<String> expandedNodeIds = {};

  /// Flattened visible rows, in display order.
  final List<String> visibleNodeIds = [];

  /// Row offset of each visible id, kept in sync so lookups stay O(1).
  final Map<String, int> _visibleIndexById = {};

  int get length => visibleNodeIds.length;
  int get nodeCount => nodeById.length;

  TreeNodeModel? node(String id) => nodeById[id];
  bool isExpanded(String id) => expandedNodeIds.contains(id);
  int? visibleIndexOf(String id) => _visibleIndexById[id];

  /// Ids of [parentId]'s children, or the roots when null.
  List<String> childrenOf(String? parentId) =>
      List.unmodifiable(childrenByParent[parentId] ?? const []);

  /// Depth of [id] from the root, used for row indentation.
  int depthOf(String id) {
    var depth = 0;
    var current = nodeById[id]?.parentId;
    while (current != null) {
      depth++;
      current = nodeById[current]?.parentId;
    }
    return depth;
  }

  /// Replaces the whole tree from a snapshot. This is the only full rebuild.
  void reset(List<TreeNodeModel> nodes, {Set<String>? expanded}) {
    nodeById.clear();
    childrenByParent.clear();
    expandedNodeIds.clear();
    if (expanded != null) expandedNodeIds.addAll(expanded);
    for (final node in nodes) {
      nodeById[node.id] = node;
      (childrenByParent[node.parentId] ??= []).add(node.id);
    }
    _rebuildVisible();
  }

  void _rebuildVisible() {
    visibleNodeIds.clear();
    _visibleIndexById.clear();
    void walk(String? parentId) {
      for (final id in childrenByParent[parentId] ?? const <String>[]) {
        _visibleIndexById[id] = visibleNodeIds.length;
        visibleNodeIds.add(id);
        if (expandedNodeIds.contains(id)) walk(id);
      }
    }

    walk(null);
  }

  /// Reindexes from [from] onward after a splice.
  void _reindexFrom(int from) {
    for (var i = from; i < visibleNodeIds.length; i++) {
      _visibleIndexById[visibleNodeIds[i]] = i;
    }
  }

  /// Visible descendants of [id] in display order (respecting expansion).
  List<String> _visibleDescendants(String id) {
    final result = <String>[];
    void walk(String parentId) {
      for (final child in childrenByParent[parentId] ?? const <String>[]) {
        result.add(child);
        if (expandedNodeIds.contains(child)) walk(child);
      }
    }

    if (expandedNodeIds.contains(id)) walk(id);
    return result;
  }

  /// Expands [id], splicing its visible descendants in after its row.
  ///
  /// Returns the number of rows inserted; 0 when already expanded, hidden, or
  /// the node has no loaded children.
  int expand(String id) {
    if (expandedNodeIds.contains(id)) return 0;
    final at = _visibleIndexById[id];
    if (at == null) return 0;
    expandedNodeIds.add(id);
    final descendants = _visibleDescendants(id);
    if (descendants.isEmpty) return 0;
    visibleNodeIds.insertAll(at + 1, descendants);
    _reindexFrom(at + 1);
    return descendants.length;
  }

  /// Records that [id] should be expanded without splicing any rows yet.
  ///
  /// Used for lazy expansion: `requestChildren` has been fired and the
  /// children will arrive asynchronously (via [attachChildren] or a full
  /// reset), at which point the rows splice in automatically.
  void markExpanded(String id) {
    if (expandedNodeIds.contains(id)) return;
    expandedNodeIds.add(id);
  }

  /// Collapses [id], removing its descendant rows.
  ///
  /// Descendants keep their own expansion state so re-expanding restores the
  /// previous shape.
  int collapse(String id) {
    if (!expandedNodeIds.contains(id)) return 0;
    final at = _visibleIndexById[id];
    final descendants = _visibleDescendants(id);
    expandedNodeIds.remove(id);
    if (at == null || descendants.isEmpty) return 0;
    visibleNodeIds.removeRange(at + 1, at + 1 + descendants.length);
    for (final removed in descendants) {
      _visibleIndexById.remove(removed);
    }
    _reindexFrom(at + 1);
    return descendants.length;
  }

  bool toggle(String id) {
    if (expandedNodeIds.contains(id)) {
      collapse(id);
      return false;
    }
    expand(id);
    return true;
  }

  /// Inserts [node] under its parent at [at], updating the visible index only
  /// when the row is actually on screen.
  void insert(TreeNodeModel node, {int? at}) {
    nodeById[node.id] = node;
    final siblings = childrenByParent[node.parentId] ??= [];
    final index = (at == null || at > siblings.length) ? siblings.length : at;
    siblings.insert(index, node.id);

    // Only splice when the parent is visible and expanded (or it is a root).
    final parentId = node.parentId;
    if (parentId != null &&
        (!expandedNodeIds.contains(parentId) ||
            !_visibleIndexById.containsKey(parentId))) {
      return;
    }
    final rowAt = _visibleRowForNewChild(parentId, index);
    if (rowAt == null) return;
    visibleNodeIds.insert(rowAt, node.id);
    _reindexFrom(rowAt);
  }

  /// Row where a new child at sibling position [index] should appear.
  int? _visibleRowForNewChild(String? parentId, int index) {
    final siblings = childrenByParent[parentId] ?? const <String>[];
    // Anchor after the preceding sibling's last visible descendant.
    for (var i = index - 1; i >= 0; i--) {
      final previous = siblings[i];
      final previousRow = _visibleIndexById[previous];
      if (previousRow != null) {
        return previousRow + 1 + _visibleDescendants(previous).length;
      }
    }
    if (parentId == null) return 0;
    final parentRow = _visibleIndexById[parentId];
    return parentRow == null ? null : parentRow + 1;
  }

  /// Removes [id] and its subtree.
  void remove(String id) {
    final node = nodeById[id];
    if (node == null) return;
    final row = _visibleIndexById[id];
    if (row != null) {
      final span = 1 + _visibleDescendants(id).length;
      final removed = visibleNodeIds.sublist(row, row + span);
      visibleNodeIds.removeRange(row, row + span);
      for (final gone in removed) {
        _visibleIndexById.remove(gone);
      }
      _reindexFrom(row);
    }
    childrenByParent[node.parentId]?.remove(id);
    _forgetSubtree(id);
  }

  void _forgetSubtree(String id) {
    for (final child in List<String>.from(childrenByParent[id] ?? const [])) {
      _forgetSubtree(child);
    }
    childrenByParent.remove(id);
    expandedNodeIds.remove(id);
    nodeById.remove(id);
  }

  /// Moves [id] to [newParentId] at sibling position [at].
  void move(String id, {String? newParentId, int? at}) {
    final node = nodeById[id];
    if (node == null) return;
    final wasExpanded = expandedNodeIds.contains(id);
    final subtree = _detachSubtree(id);
    final moved = TreeNodeModel(
      id: node.id,
      label: node.label,
      parentId: newParentId,
      icon: node.icon,
      hasChildren: node.hasChildren,
      childrenState: node.childrenState,
      data: node.data,
    );
    insert(moved, at: at);
    // Reattach the original children under the moved node.
    childrenByParent[id] = subtree;
    if (wasExpanded) {
      expandedNodeIds.add(id);
      final row = _visibleIndexById[id];
      if (row != null) {
        expandedNodeIds.remove(id);
        expand(id);
      }
    }
  }

  /// Detaches [id] from the tree, returning its child ids.
  List<String> _detachSubtree(String id) {
    final node = nodeById[id];
    if (node == null) return const [];
    final row = _visibleIndexById[id];
    if (row != null) {
      final span = 1 + _visibleDescendants(id).length;
      final removed = visibleNodeIds.sublist(row, row + span);
      visibleNodeIds.removeRange(row, row + span);
      for (final gone in removed) {
        _visibleIndexById.remove(gone);
      }
      _reindexFrom(row);
    }
    childrenByParent[node.parentId]?.remove(id);
    final children = childrenByParent.remove(id) ?? <String>[];
    expandedNodeIds.remove(id);
    nodeById.remove(id);
    return children;
  }

  /// Relabels a node in place. Deliberately does not touch the visible index —
  /// the widget layer repaints one row.
  bool relabel(String id, String label) {
    final node = nodeById[id];
    if (node == null) return false;
    node.label = label;
    return true;
  }

  /// Marks [id]'s children as loading / loaded / failed.
  void setChildrenState(String id, ChildrenState state) {
    nodeById[id]?.childrenState = state;
  }

  /// Attaches lazily-fetched [children] under [parentId].
  ///
  /// When the parent is expanded the new rows splice in; otherwise they stay
  /// off-screen until it is.
  void attachChildren(String parentId, List<TreeNodeModel> children) {
    final parent = nodeById[parentId];
    if (parent == null) return;
    parent.childrenState = ChildrenState.loaded;
    parent.hasChildren = parent.hasChildren || children.isNotEmpty;
    final wasExpanded = expandedNodeIds.remove(parentId);
    childrenByParent[parentId] = [for (final child in children) child.id];
    for (final child in children) {
      nodeById[child.id] = child;
    }
    if (wasExpanded) expand(parentId);
  }

  /// Whether expanding [id] needs a `requestChildren` round-trip.
  bool needsChildren(String id) {
    final node = nodeById[id];
    return node != null &&
        node.hasChildren &&
        node.childrenState == ChildrenState.unloaded &&
        (childrenByParent[id] ?? const []).isEmpty;
  }

  void clear() {
    nodeById.clear();
    childrenByParent.clear();
    expandedNodeIds.clear();
    visibleNodeIds.clear();
    _visibleIndexById.clear();
  }
}

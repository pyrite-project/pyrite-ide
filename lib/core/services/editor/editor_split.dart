import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/workspace_pane.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// The editor area's layout: a single group, or a tree of splits.
///
/// Every group is a [TabbedViewController] that lives as long as the group and
/// is changed in place, so a leaf holds its controller directly. The tree
/// itself is immutable; only [EditorLayoutNotifier] replaces it.
sealed class EditorLayout {
  const EditorLayout();

  /// Every group in the tree, in layout order.
  Iterable<TabbedViewController> get controllers;

  /// Every tab of every group, in layout order.
  Iterable<TabData> get tabs => controllers.expand((group) => group.tabs);

  /// Whether [group] is one of the tree's groups.
  bool contains(TabbedViewController group) =>
      controllers.any((candidate) => identical(candidate, group));
}

/// A leaf: one group and its tab strip.
class GroupLayout extends EditorLayout {
  const GroupLayout(this.controller);

  final TabbedViewController controller;

  @override
  Iterable<TabbedViewController> get controllers => [controller];

  @override
  bool operator ==(Object other) =>
      other is GroupLayout && identical(other.controller, controller);

  @override
  int get hashCode => identityHashCode(controller);
}

/// A split whose [children] are laid out along [axis].
class SplitLayout extends EditorLayout {
  /// [weights] are the children's relative sizes, one per child; equal shares
  /// when omitted.
  SplitLayout(this.axis, this.children, [List<double>? weights])
    : assert(children.length >= 2),
      assert(weights == null || weights.length == children.length),
      weights = List.unmodifiable(weights ?? List.filled(children.length, 1.0));

  final Axis axis;
  final List<EditorLayout> children;

  /// The share of the split each child takes, relative to the others.
  ///
  /// Kept in the tree so a resize survives the next reshape and a restart.
  final List<double> weights;

  @override
  Iterable<TabbedViewController> get controllers =>
      children.expand((child) => child.controllers);

  @override
  bool operator ==(Object other) =>
      other is SplitLayout &&
      other.axis == axis &&
      listEquals(other.children, children) &&
      listEquals(other.weights, weights);

  @override
  int get hashCode =>
      Object.hash(axis, Object.hashAll(children), Object.hashAll(weights));
}

/// The share a group split off by a drop takes of the space it splits.
///
/// [EditorSplitHint] previews exactly this share, so the drop lands where the
/// preview promised.
const double newEditorGroupShare = 0.4;

/// The editor area's layout. One group until a tab is dropped on an edge.
final StateNotifierProvider<EditorLayoutNotifier, EditorLayout>
editorLayoutProvider =
    StateNotifierProvider<EditorLayoutNotifier, EditorLayout>(
      (ref) => EditorLayoutNotifier(ref),
    );

/// The group the user last worked in, or null before any group took focus.
final StateProvider<TabbedViewController?> focusedEditorGroupProvider =
    StateProvider<TabbedViewController?>((ref) => null);

/// The group the shared editing commands act on.
///
/// The focused group while it is still in the tree, the primary group
/// otherwise -- which covers every session that never split.
final Provider<TabbedViewController> activeEditorControllerProvider =
    Provider<TabbedViewController>((ref) {
      final layout = ref.watch(editorLayoutProvider);
      final focused = ref.watch(focusedEditorGroupProvider);
      if (focused != null && layout.contains(focused)) return focused;
      // The primary controller is never replaced, so there is nothing to
      // watch -- and watching its provider would make every read of this one
      // from inside the tab notifier a dependency cycle.
      return ref.read(editorLayoutProvider.notifier).primary;
    });

/// The tab the shared editing commands act on, with the group holding it.
///
/// Deliberately without value equality: [activeEditorTabProvider] hands out a
/// new instance on every change of the group, and that new instance is what
/// tells its dependents something moved.
@immutable
class ActiveEditorTab {
  const ActiveEditorTab(this.group, this.tab);

  final TabbedViewController group;
  final TabData? tab;

  /// The document behind [tab], or null when the tab is not a document.
  TabDataValue? get value => editorTabValueOf(tab);
}

/// The active group's selected tab, kept current as that group changes.
///
/// Groups are changed in place -- a tab selected, opened, closed or marked
/// modified -- so a provider handing out the controller itself never reports
/// any of it. This one rebuilds on every change of the active group.
final Provider<ActiveEditorTab> activeEditorTabProvider =
    Provider<ActiveEditorTab>((ref) {
      final group = ref.watch(activeEditorControllerProvider);
      group.addListener(ref.invalidateSelf);
      ref.onDispose(() => group.removeListener(ref.invalidateSelf));
      return ActiveEditorTab(group, group.selectedTab);
    });

/// Every editor group, in layout order.
List<TabbedViewController> allEditorControllers(ProviderContainer container) =>
    container.read(editorLayoutProvider).controllers.toList();

/// Every tab of every editor group, in layout order.
///
/// Whatever has to see all open tabs -- the unsaved guard, persistence, title
/// disambiguation -- walks this, or a tab parked in another group is missed.
List<TabData> allEditorTabs(ProviderContainer container) =>
    container.read(editorLayoutProvider).tabs.toList();

/// Whether [tab] may leave its group.
///
/// The welcome page is pinned -- `draggable: false` -- because it is the
/// editor's floor: it can be neither closed nor moved, which is also what
/// keeps the primary group from ever being pruned.
bool canTabLeaveGroup(TabData tab) => tab.draggable;

/// Owns the editor area's layout tree and keeps it well-formed.
///
/// Every rewrite goes through [_commit], which drops groups that lost their
/// last tab, collapses splits left with one child, brings the primary group
/// back when it holds tabs while out of the tree, keeps the focused group
/// valid and refreshes the tab titles. The groups are watched as well, since
/// tabs leave a group through its own controller -- the close button, a
/// context menu, a drop onto another strip, the SDK -- without passing here.
class EditorLayoutNotifier extends StateNotifier<EditorLayout> {
  EditorLayoutNotifier(this._ref)
    : super(GroupLayout(_ref.read(tabbedViewControllerProvider))) {
    _followGroups();
  }

  final Ref _ref;
  final Set<TabbedViewController> _followed = {};
  final _Signal _changes = _Signal();

  /// Above zero while this notifier is changing groups itself; the group
  /// listeners stay quiet then, and the change commits once, at the end.
  int _muted = 0;

  /// Fires whenever anything in the editor area changes: a tab of any group,
  /// the set of groups, or their sizes.
  ///
  /// For whatever has to see the whole area -- persistence, the plugin
  /// document registry -- so it does not have to follow each group itself.
  Listenable get changes => _changes;

  /// The group the welcome page lives in, and the one new tabs fall back to
  /// while no group has focus.
  TabbedViewController get primary => _ref.read(tabbedViewControllerProvider);

  /// Whether dropping [tab] on [target]'s edge would really split it.
  ///
  /// Asked for the drop preview and again by [splitGroup], so a preview is
  /// only shown for a drop that will be honoured. [from] is wherever the tab
  /// lives now: the docked console panel is a group outside the tree.
  bool canSplitGroup({
    required TabbedViewController from,
    required TabbedViewController target,
    required TabData tab,
  }) {
    if (!canTabLeaveGroup(tab) || !from.tabs.contains(tab)) return false;
    if (!state.contains(target)) return false;
    // Splitting a group's own last tab out would empty it, and pruning would
    // then undo the split.
    return !identical(from, target) || from.tabs.length >= 2;
  }

  /// Splits [target] towards [where] and moves [tab] into the new group.
  bool splitGroup({
    required TabbedViewController from,
    required TabbedViewController target,
    required TabData tab,
    required PaneEdge where,
  }) {
    if (!canSplitGroup(from: from, target: target, tab: tab)) return false;
    _apply(() {
      final created = _detachIntoNewGroup(from, tab);
      final split = _beside(GroupLayout(target), created, where);
      return (layout: _replaceGroup(state, target, split), focus: created);
    });
    return true;
  }

  /// Whether dropping [tab] on the editor area's boundary would split it.
  bool canSplitArea({
    required TabbedViewController from,
    required TabData tab,
  }) => canTabLeaveGroup(tab) && from.tabs.contains(tab);

  /// Splits the editor area itself: [tab] moves into a new group placed
  /// beside the whole current tree along [where]'s axis.
  ///
  /// A leaf's edge bands only ever split that leaf, and every ancestor has its
  /// edges covered by its children's, so this is the only gesture that adds a
  /// group above the top-level split.
  bool splitArea({
    required TabbedViewController from,
    required TabData tab,
    required PaneEdge where,
  }) {
    if (!canSplitArea(from: from, tab: tab)) return false;
    _apply(() {
      final created = _detachIntoNewGroup(from, tab);
      return (layout: _beside(state, created, where), focus: created);
    });
    return true;
  }

  /// Moves [tab] to the end of [into] and shows it there.
  ///
  /// Returns false when the tab is already in [into]: the strip's own drop
  /// regions reorder tabs inside a group.
  bool moveTab({
    required TabbedViewController from,
    required TabData tab,
    required TabbedViewController into,
  }) {
    if (identical(from, into)) return false;
    final index = from.tabs.indexOf(tab);
    if (index < 0 || !canTabLeaveGroup(tab)) return false;
    _apply(() {
      from.removeTab(index);
      into.addTab(tab);
      into.selectedIndex = into.tabs.length - 1;
      return (layout: state, focus: into);
    });
    return true;
  }

  /// Whether [group]'s edge on [where]'s side is the editor area's boundary.
  ///
  /// Walking down to the group, a split running along [where]'s axis keeps
  /// the boundary only while the group sits in the child on that side, and a
  /// split running across it is spanned and leaves the answer to the child.
  /// Groups outside the tree -- the docked console panel -- are never on it.
  bool isAtAreaEdge(TabbedViewController group, PaneEdge where) =>
      _atAreaEdge(state, group, where);

  /// Makes [group] the one the shared editing commands act on.
  void focus(TabbedViewController group) {
    if (!state.contains(group)) return;
    final focused = _ref.read(focusedEditorGroupProvider.notifier);
    if (!identical(focused.state, group)) focused.state = group;
    _ref
        .read(focusedWorkspacePaneProvider.notifier)
        .state = WorkspacePane.editor;
  }

  /// Replaces the whole tree, as a session restore does.
  void replace(EditorLayout layout) => _commit(layout);

  /// Records the shares a resize left [split]'s children with.
  ///
  /// [weights] are the children's sizes, in any unit. Without this, the next
  /// reshape of the tree -- or a restart -- would split the space evenly again.
  void resizeSplit(SplitLayout split, List<double> weights) {
    if (weights.length != split.children.length) return;
    if (weights.any((weight) => !(weight > 0) || weight.isInfinite)) return;
    final resized = _resized(state, split, weights);
    if (resized == null) return;
    state = resized;
    _changes.notify();
  }

  @override
  void dispose() {
    for (final group in _followed) {
      group.removeListener(_onGroupChanged);
    }
    _followed.clear();
    _changes.dispose();
    super.dispose();
  }

  /// Runs [change] with the group listeners muted, then commits its result.
  void _apply(
    ({EditorLayout layout, TabbedViewController? focus}) Function() change,
  ) {
    final ({EditorLayout layout, TabbedViewController? focus}) result;
    _muted++;
    try {
      result = change();
    } finally {
      _muted--;
    }
    _commit(result.layout, focus: result.focus);
  }

  void _commit(EditorLayout next, {TabbedViewController? focus}) {
    _muted++;
    try {
      final normalized = _normalize(next);
      if (normalized != state) state = normalized;
      _followGroups();
      final focused = _ref.read(focusedEditorGroupProvider.notifier);
      final current = focused.state;
      if (focus != null && state.contains(focus)) {
        if (!identical(current, focus)) focused.state = focus;
        _ref
            .read(focusedWorkspacePaneProvider.notifier)
            .state = WorkspacePane.editor;
      } else if (current != null && !state.contains(current)) {
        focused.state = null;
      }
      // Which names collide depends on which tabs are open, in every group.
      refreshFileTabTitles(state.tabs);
    } finally {
      _muted--;
    }
    _changes.notify();
  }

  /// Whether the tree already satisfies what [_commit] establishes.
  bool get _isNormalized {
    final groups = state.controllers.toList();
    if (groups.length > 1 && groups.any((group) => group.tabs.isEmpty)) {
      return false;
    }
    return primary.tabs.isEmpty || state.contains(primary);
  }

  void _onGroupChanged() {
    if (_muted > 0) return;
    if (_isNormalized) {
      _changes.notify();
    } else {
      _commit(state);
    }
  }

  /// Follows every group in the tree, and the primary even while it is out of
  /// the tree: new tabs fall back to it, and it has to come back as soon as it
  /// holds one.
  void _followGroups() {
    final live = {...state.controllers, primary};
    for (final group in live) {
      if (_followed.add(group)) group.addListener(_onGroupChanged);
    }
    _followed.removeWhere((group) {
      if (live.contains(group)) return false;
      group.removeListener(_onGroupChanged);
      return true;
    });
  }

  /// [layout] with empty and repeated groups dropped, single-child splits
  /// collapsed and the primary group brought back when it holds tabs.
  ///
  /// The last group is kept even when empty, so the area always has a strip.
  EditorLayout _normalize(EditorLayout layout) {
    final pruned = _prune(layout, {}) ?? GroupLayout(primary);
    if (primary.tabs.isEmpty || pruned.contains(primary)) return pruned;
    return SplitLayout(
      Axis.horizontal,
      [GroupLayout(primary), pruned],
      const [newEditorGroupShare, 1 - newEditorGroupShare],
    );
  }
}

/// A [ChangeNotifier] whose notification is public to its owner.
class _Signal extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Moves [tab] out of [from] into a new group of its own.
///
/// The tab has to leave [from] before the new controller is built: a
/// [TabData] stores the index its owner gave it and `removeTab` resets that to
/// -1, so a controller built first would hold a tab whose index reads -1 and
/// throw on the first `selectTab`.
TabbedViewController _detachIntoNewGroup(
  TabbedViewController from,
  TabData tab,
) {
  from.removeTab(from.tabs.indexOf(tab));
  return TabbedViewController([tab]);
}

/// [existing] and a new leaf for [created], side by side along [where].
///
/// The new group takes [newEditorGroupShare] of the space, which is what the
/// drop preview showed.
SplitLayout _beside(
  EditorLayout existing,
  TabbedViewController created,
  PaneEdge where,
) {
  const share = newEditorGroupShare;
  return where.isLeading
      ? SplitLayout(
          where.axis,
          [GroupLayout(created), existing],
          const [share, 1 - share],
        )
      : SplitLayout(
          where.axis,
          [existing, GroupLayout(created)],
          const [1 - share, share],
        );
}

/// [node] with the group [target] swapped for [replacement].
EditorLayout _replaceGroup(
  EditorLayout node,
  TabbedViewController target,
  EditorLayout replacement,
) => switch (node) {
  GroupLayout(:final controller) =>
    identical(controller, target) ? replacement : node,
  SplitLayout(:final axis, :final children, :final weights) => SplitLayout(
    axis,
    [for (final child in children) _replaceGroup(child, target, replacement)],
    weights,
  ),
};

/// [node] with [split] given [weights], or null when [split] is not in it.
EditorLayout? _resized(
  EditorLayout node,
  SplitLayout split,
  List<double> weights,
) {
  if (identical(node, split)) {
    return SplitLayout(split.axis, split.children, weights);
  }
  if (node is! SplitLayout) return null;
  for (var i = 0; i < node.children.length; i++) {
    final child = _resized(node.children[i], split, weights);
    if (child == null) continue;
    return SplitLayout(node.axis, [
      for (var j = 0; j < node.children.length; j++)
        j == i ? child : node.children[j],
    ], node.weights);
  }
  return null;
}

bool _atAreaEdge(
  EditorLayout node,
  TabbedViewController group,
  PaneEdge where,
) {
  switch (node) {
    case GroupLayout(:final controller):
      return identical(controller, group);
    case SplitLayout(:final axis, :final children):
      for (var i = 0; i < children.length; i++) {
        if (!_atAreaEdge(children[i], group, where)) continue;
        if (axis != where.axis) return true;
        return where.isLeading ? i == 0 : i == children.length - 1;
      }
      return false;
  }
}

/// [node] without empty groups, groups already in [seen] and single-child
/// splits, or null when nothing in it survives.
EditorLayout? _prune(EditorLayout node, Set<TabbedViewController> seen) {
  switch (node) {
    case GroupLayout(:final controller):
      // A group listed twice -- only a damaged restore produces that -- would
      // render one controller in two strips.
      if (controller.tabs.isEmpty || !seen.add(controller)) return null;
      return node;
    case SplitLayout(:final axis, :final children, :final weights):
      final kept = <EditorLayout>[];
      final keptWeights = <double>[];
      for (var i = 0; i < children.length; i++) {
        final pruned = _prune(children[i], seen);
        if (pruned == null) continue;
        kept.add(pruned);
        keptWeights.add(weights[i]);
      }
      if (kept.isEmpty) return null;
      if (kept.length == 1) return kept.single;
      // The survivors keep their sizes relative to each other; the space the
      // dropped children had is shared out in proportion.
      return SplitLayout(axis, kept, keptWeights);
  }
}

/// The tree as persisted groups plus a [PersistedEditorLayout] node.
///
/// [convert] is called once per group in layout order and the results are
/// numbered in that order, so the flat list and the tree always agree.
/// `primaryIndex` is where [primary] landed: a restore hands the primary role
/// -- the welcome page, the fallback for new tabs -- back to that group rather
/// than to whichever group happens to come first.
({
  List<PersistedEditorGroup> groups,
  PersistedEditorLayout node,
  int primaryIndex,
})
persistEditorLayout(
  EditorLayout layout, {
  required TabbedViewController primary,
  required PersistedEditorGroup Function(TabbedViewController group) convert,
}) {
  final groups = <PersistedEditorGroup>[];
  var primaryIndex = 0;
  PersistedEditorLayout visit(EditorLayout node) {
    switch (node) {
      case GroupLayout(:final controller):
        if (identical(controller, primary)) primaryIndex = groups.length;
        groups.add(convert(controller));
        return PersistedEditorLayout.group(groups.length - 1);
      case SplitLayout(:final axis, :final children, :final weights):
        return PersistedEditorLayout.split(axis.name, [
          for (final child in children) visit(child),
        ], weights: weights);
    }
  }

  final node = visit(layout);
  return (groups: groups, node: node, primaryIndex: primaryIndex);
}

/// Rebuilds the tree persisted as [groups] and [node].
///
/// The group at [primaryIndex] is [primary] itself; every other group gets a
/// fresh controller for the caller to seed (seeding is async, so it cannot
/// happen here). The returned `controllers` are the exact instances wired into
/// the tree, one per persisted group. Leaves pointing past [groups], or at a
/// group another leaf already took, are dropped, so a damaged session still
/// opens.
({EditorLayout node, List<TabbedViewController> controllers})
restoreEditorLayout(
  List<PersistedEditorGroup> groups,
  PersistedEditorLayout? node, {
  required TabbedViewController primary,
  int primaryIndex = 0,
}) {
  if (node == null || !node.isSplit || groups.isEmpty) {
    return (node: GroupLayout(primary), controllers: [primary]);
  }

  final primaryAt = primaryIndex.clamp(0, groups.length - 1);
  final controllers = [
    for (var i = 0; i < groups.length; i++)
      i == primaryAt ? primary : TabbedViewController([]),
  ];
  final used = <int>{};
  final axes = Axis.values.asNameMap();

  EditorLayout? build(PersistedEditorLayout n) {
    if (!n.isSplit) {
      final index = n.groupIndex ?? 0;
      if (index < 0 || index >= controllers.length || !used.add(index)) {
        return null;
      }
      return GroupLayout(controllers[index]);
    }
    final saved = n.weights;
    final children = <EditorLayout>[];
    final weights = <double>[];
    for (var i = 0; i < n.children.length; i++) {
      final built = build(n.children[i]);
      if (built == null) continue;
      children.add(built);
      final weight = saved != null && i < saved.length ? saved[i] : 1.0;
      weights.add(weight > 0 && weight.isFinite ? weight : 1.0);
    }
    if (children.isEmpty) return null;
    if (children.length == 1) return children.single;
    return SplitLayout(axes[n.axis] ?? Axis.horizontal, children, weights);
  }

  return (node: build(node) ?? GroupLayout(primary), controllers: controllers);
}

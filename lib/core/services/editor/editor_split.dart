import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// Where a dropped tab splits the group it landed on.
enum EditorSplit {
  left,
  top,
  right,
  bottom;

  /// The axis the group splits along.
  Axis get axis => switch (this) {
    EditorSplit.left || EditorSplit.right => Axis.horizontal,
    EditorSplit.top || EditorSplit.bottom => Axis.vertical,
  };

  /// Whether the new group goes before the one it was split from.
  bool get secondaryFirst => switch (this) {
    EditorSplit.left || EditorSplit.top => true,
    EditorSplit.right || EditorSplit.bottom => false,
  };
}

/// The editor area's layout: a single group, or a tree of splits.
///
/// Only a drag rewrites the tree, and every rewrite replaces it wholesale --
/// which is what lets a group be split again inside itself.
sealed class EditorLayout {
  const EditorLayout();

  /// Every group in the tree, in layout order.
  ///
  /// [primary] is the controller new tabs open in; the primary leaf resolves
  /// against it because that controller is not stable across operations.
  Iterable<TabbedViewController> controllers(TabbedViewController primary);
}

/// A leaf bound to one controller instance.
///
/// Used for every group except the primary one, whose controller is swapped
/// for a fresh instance by nearly every tab operation.
class GroupLayout extends EditorLayout {
  const GroupLayout(this.controller);

  final TabbedViewController controller;

  @override
  Iterable<TabbedViewController> controllers(TabbedViewController primary) => [
    controller,
  ];
}

/// The group new tabs open in.
///
/// Held as a role rather than an instance: [tabbedViewControllerProvider]
/// publishes a brand-new controller on almost every tab operation, so an
/// instance captured here would strand the strip on a dead controller and
/// leave a stale twin of the group on screen.
class PrimaryGroupLayout extends EditorLayout {
  const PrimaryGroupLayout();

  @override
  Iterable<TabbedViewController> controllers(TabbedViewController primary) => [
    primary,
  ];
}

/// A split whose [children] are laid out along [axis].
class SplitLayout extends EditorLayout {
  const SplitLayout(this.axis, this.children) : assert(children.length >= 2);

  final Axis axis;
  final List<EditorLayout> children;

  @override
  Iterable<TabbedViewController> controllers(TabbedViewController primary) => [
    for (final child in children) ...child.controllers(primary),
  ];
}

/// The editor area's layout. One group until a tab is dropped on an edge.
final StateProvider<EditorLayout> editorLayoutProvider =
    StateProvider<EditorLayout>((ref) => const PrimaryGroupLayout());

/// The controller a group leaf renders.
TabbedViewController groupController(
  ProviderContainer container,
  EditorLayout node,
) {
  if (node is PrimaryGroupLayout) {
    return container.read(tabbedViewControllerProvider);
  }
  if (node is GroupLayout) return node.controller;
  throw ArgumentError.value(node, 'node', 'a split has no controller');
}

/// The group the shared editing commands act on, or null for the only group.
final StateProvider<TabbedViewController?> focusedEditorGroupProvider =
    StateProvider<TabbedViewController?>((ref) => null);

/// The group the shared editing commands act on.
///
/// Falls back to the primary group whenever nothing is focused or the focused
/// group has since been dropped, which is every session that never split and
/// keeps every existing caller on its old target.
final Provider<TabbedViewController> activeEditorControllerProvider =
    Provider<TabbedViewController>((ref) {
      final focused = ref.watch(focusedEditorGroupProvider);
      final primary = ref.watch(tabbedViewControllerProvider);
      if (focused != null &&
          ref
              .watch(editorLayoutProvider)
              .controllers(primary)
              .contains(focused)) {
        return focused;
      }
      return primary;
    });

/// Every group that holds tabs.
///
/// Anything that has to see *all* open tabs -- the unsaved guard, tab
/// persistence -- has to walk the tree, or a tab parked in a nested group
/// would be missed.
List<TabbedViewController> allEditorControllers(ProviderContainer container) {
  return container
      .read(editorLayoutProvider)
      .controllers(container.read(tabbedViewControllerProvider))
      .toList();
}

/// Every tab of every group, in layout order.
///
/// Titles are disambiguated across the whole editor area, because a name that
/// is unique inside its own group can still collide with a tab in another one.
/// Refreshing a single group's tabs is what left two identical titles on
/// screen -- and a tab dragged out of a group stuck with the long title it had
/// been given there, since nothing ever shortened it back.
List<TabData> allEditorTabs(ProviderContainer container) {
  return [
    for (final controller in allEditorControllers(container))
      ...controller.tabs,
  ];
}

/// Whether [tab] may leave its group.
///
/// The welcome page is pinned -- `draggable: false` -- because it is the
/// editor's floor: it can be neither closed nor moved, and a group holding
/// nothing else keeps it rather than being pruned away.
bool canTabLeaveGroup(TabData tab) => tab.draggable;

/// Moves [tab] into the group that has focus, if that is not [from].
///
/// Tabs are built on the primary controller because that is the provider the
/// tab notifier is bound to; a split editor should open the file in the group
/// the user is looking at. Only the creation paths route through here --
/// saving, closing and restoring all keep working on the primary group.
///
/// Returns whether the tab moved, so the caller knows to republish [from].
bool moveTabToFocusedGroup(
  ProviderContainer container, {
  required TabbedViewController from,
  required TabData tab,
}) {
  final focused = container.read(activeEditorControllerProvider);
  if (identical(focused, from)) return false;

  final index = from.tabs.indexOf(tab);
  if (index < 0) return false;
  // A pinned tab never moves, whatever asked for it.
  if (!canTabLeaveGroup(tab)) return false;

  // The tab the user was looking at in [from] must survive the move.
  final selected = from.selectedTab;
  final selectedIndex = from.selectedIndex;
  from.removeTab(index);
  focused.insertTab(focused.tabs.length, tab);
  focused.selectTab(tab);
  if (selected != null && from.tabs.contains(selected)) {
    from.selectTab(selected);
  } else if (from.selectedIndex == null && from.tabs.isNotEmpty) {
    // [selected] left together with the move, and [from] had no other tab to
    // fall back to, so it is left with nothing selected. `removeTab` only
    // restores a selection when one existed.
    from.selectedIndex = (selectedIndex ?? 0).clamp(0, from.tabs.length - 1);
  }
  return true;
}

/// Moves [tab] into [into], dropping the group it came from if that empties.
///
/// Returns false when the tab is already in [into]; the strip's own drop
/// regions handle reordering inside a group.
bool moveTabToEditorGroup(
  ProviderContainer container, {
  required TabbedViewController from,
  required TabData tab,
  required TabbedViewController into,
}) {
  if (identical(from, into)) return false;
  final index = from.tabs.indexOf(tab);
  if (index < 0) return false;
  // A pinned tab never moves, whatever asked for it.
  if (!canTabLeaveGroup(tab)) return false;

  from.removeTab(index);
  into.insertTab(into.tabs.length, tab);
  into.selectTab(tab);
  container.read(focusedEditorGroupProvider.notifier).state = into;
  _refreshLayout(container);
  return true;
}

/// Whether dropping [tab] on [target]'s edge would really split.
///
/// Asked twice: once to decide whether to show the drop preview, and once
/// again on the drop itself. Showing a preview the drop cannot honour is what
/// used to make a split look accepted and then silently do nothing.
///
/// [from] is wherever the tab currently lives -- a console tab comes from the
/// docked panel, which is a group the editor layout does not contain.
bool canSplitEditorGroup({
  required TabbedViewController from,
  required TabbedViewController target,
  required TabData tab,
}) {
  // Splitting a group's own last tab would empty it, and pruning would then
  // undo the split -- refuse it rather than pretend it happened.
  return !identical(from, target) || from.tabs.length >= 2;
}

/// Splits the group [target] towards [where] and moves [tab] into the new one.
///
/// [tab] comes from [from], which need not be [target]: dragging across groups
/// onto an edge is the usual way to open a new group, and the docked console
/// panel is a group too even though it is not a node of the editor layout.
bool splitEditorGroup(
  ProviderContainer container, {
  required TabbedViewController from,
  required TabbedViewController target,
  required TabData tab,
  required EditorSplit where,
}) {
  if (identical(from, target) && from.tabs.length < 2) return false;
  // A pinned tab never moves, so it is never split out either.
  if (!canTabLeaveGroup(tab)) return false;
  // The source controller was captured when the drag started, and the primary
  // is republished by nearly every tab operation: the tab may have closed or
  // the controller been swapped since. `removeTab` validates its index.
  if (from.tabs.indexOf(tab) < 0) return false;

  final created = TabbedViewController([tab]);
  from.removeTab(from.tabs.indexOf(tab));

  final replacement = SplitLayout(where.axis, [
    if (where.secondaryFirst) GroupLayout(created),
    _leafFor(container, target),
    if (!where.secondaryFirst) GroupLayout(created),
  ]);
  container.read(editorLayoutProvider.notifier).state = _replaceGroup(
    container,
    container.read(editorLayoutProvider),
    target,
    replacement,
  );
  container.read(focusedEditorGroupProvider.notifier).state = created;
  // The tab may have been the last one where it came from; that group goes.
  _refreshLayout(container);
  return true;
}

/// Whether dropping [tab] on the editor area's boundary would really split it.
bool canSplitEditorArea({
  required TabbedViewController from,
  required TabData tab,
}) {
  return canTabLeaveGroup(tab) && from.tabs.contains(tab);
}

/// Splits the editor area itself: [tab] moves into a new group placed beside
/// the whole current tree along [where]'s axis.
///
/// A leaf's edge bands can only ever split the leaf they belong to, and every
/// ancestor group has its edges covered by its children's, so without this a
/// second split above the top-level one -- the root's own new child -- has no
/// gesture at all. The outermost strip of a group that sits on the area's
/// boundary is that gesture.
bool splitEditorArea(
  ProviderContainer container, {
  required TabbedViewController from,
  required TabData tab,
  required EditorSplit where,
}) {
  if (!canTabLeaveGroup(tab)) return false;
  if (from.tabs.indexOf(tab) < 0) return false;

  final created = TabbedViewController([tab]);
  from.removeTab(from.tabs.indexOf(tab));
  final current = container.read(editorLayoutProvider);
  container
      .read(editorLayoutProvider.notifier)
      .state = SplitLayout(where.axis, [
    if (where.secondaryFirst) GroupLayout(created),
    current,
    if (!where.secondaryFirst) GroupLayout(created),
  ]);
  container.read(focusedEditorGroupProvider.notifier).state = created;
  // The tab may have been the last one where it came from; that group goes.
  // The primary always survives -- the welcome page is pinned -- so the split
  // keeps both of its children.
  _refreshLayout(container);
  return true;
}

/// Whether [controller]'s edge on [where]'s side is the editor area's own
/// boundary.
///
/// Walking up from the group, a split running along [where]'s axis keeps the
/// boundary only while the group is entered through the child on that side,
/// and a split running across it is spanned and leaves the answer to its
/// parent. Groups the layout does not contain -- the docked console panel --
/// are never on it.
bool groupAtAreaEdge(
  ProviderContainer container,
  TabbedViewController controller,
  EditorSplit where,
) {
  final primary = container.read(tabbedViewControllerProvider);
  return _atAreaEdge(
    container.read(editorLayoutProvider),
    primary,
    controller,
    where,
  );
}

bool _atAreaEdge(
  EditorLayout node,
  TabbedViewController primary,
  TabbedViewController controller,
  EditorSplit where,
) {
  if (node is GroupLayout) return identical(node.controller, controller);
  if (node is PrimaryGroupLayout) return identical(primary, controller);
  final split = node as SplitLayout;
  for (var i = 0; i < split.children.length; i++) {
    if (!_atAreaEdge(split.children[i], primary, controller, where)) continue;
    // The group lives in this split.
    if (split.axis != where.axis) return true;
    return where.secondaryFirst ? i == 0 : i == split.children.length - 1;
  }
  return false;
}

/// The leaf that keeps rendering [controller] after this operation.
///
/// The primary keeps its role so the next controller the provider publishes
/// still lands in the same strip.
EditorLayout _leafFor(
  ProviderContainer container,
  TabbedViewController controller,
) {
  if (identical(controller, container.read(tabbedViewControllerProvider))) {
    return const PrimaryGroupLayout();
  }
  return GroupLayout(controller);
}

/// Rebuilds [node] with the group [target] swapped for [replacement].
EditorLayout _replaceGroup(
  ProviderContainer container,
  EditorLayout node,
  TabbedViewController target,
  EditorLayout replacement,
) {
  if (node is GroupLayout) {
    return identical(node.controller, target) ? replacement : node;
  }
  if (node is PrimaryGroupLayout) {
    return identical(groupController(container, node), target)
        ? replacement
        : node;
  }
  final split = node as SplitLayout;
  return SplitLayout(split.axis, [
    for (final child in split.children)
      _replaceGroup(container, child, target, replacement),
  ]);
}

/// Re-reads the layout so groups that just lost their last tab disappear.
void _refreshLayout(ProviderContainer container) {
  container.read(editorLayoutProvider.notifier).state = refreshEditorLayout(
    container,
  );
  // Group membership changed, so which names collide changed with it: a tab
  // that carried a long disambiguating title into a group with no rival has to
  // drop back to its basename, and vice versa.
  refreshFileTabTitles(allEditorTabs(container));
}

/// The layout as it should be: empty groups dropped, primary brought back.
EditorLayout refreshEditorLayout(ProviderContainer container) {
  return restoreEditorPrimary(
    container,
    pruneEditorGroups(container, container.read(editorLayoutProvider)),
  );
}

/// Whether the layout needs a rewrite: a group went empty while another still
/// has tabs, or the primary holds a tab it has nowhere to render.
///
/// Checked on every frame by [Editor]: tabs leave a group in ways no single
/// call site owns -- the close button, the context menu, the SDK -- so waiting
/// for a move to prune leaves an empty strip behind. The second half of the
/// test keeps an all-empty layout from scheduling itself forever.
bool needsEditorLayoutRefresh(ProviderContainer container) {
  final layout = container.read(editorLayoutProvider);
  final primary = container.read(tabbedViewControllerProvider);
  if (primary.tabs.isNotEmpty && !hasPrimaryGroupNode(layout)) return true;
  final groups = layout.controllers(primary).toList();
  return groups.any((group) => group.tabs.isEmpty) &&
      groups.any((group) => group.tabs.isNotEmpty);
}

/// Drops every group that lost its last tab and collapses single-child splits.
///
/// The last group is kept even when empty: the editor area always has a strip,
/// exactly like it did before any split existed.
EditorLayout pruneEditorGroups(ProviderContainer container, EditorLayout node) {
  final primary = container.read(tabbedViewControllerProvider);
  return _prune(container, node) ?? GroupLayout(primary);
}

EditorLayout? _prune(ProviderContainer container, EditorLayout node) {
  if (node is GroupLayout) {
    return node.controller.tabs.isEmpty ? null : node;
  }
  if (node is PrimaryGroupLayout) {
    return groupController(container, node).tabs.isEmpty ? null : node;
  }
  final split = node as SplitLayout;
  final kept = <EditorLayout>[];
  for (final child in split.children) {
    final pruned = _prune(container, child);
    if (pruned != null) kept.add(pruned);
  }
  if (kept.isEmpty) return null;
  if (kept.length == 1) return kept.single;
  return SplitLayout(split.axis, kept);
}

/// Brings the primary group back when it holds a tab while out of the tree.
///
/// New tabs always open in the primary controller, so a primary pruned while
/// empty has to reappear the moment it holds something again -- otherwise the
/// file would open into a strip nothing renders.
EditorLayout restoreEditorPrimary(
  ProviderContainer container,
  EditorLayout layout,
) {
  if (hasPrimaryGroupNode(layout)) return layout;
  final primary = container.read(tabbedViewControllerProvider);
  if (primary.tabs.isEmpty) return layout;
  return SplitLayout(Axis.horizontal, [const PrimaryGroupLayout(), layout]);
}

bool hasPrimaryGroupNode(EditorLayout node) {
  if (node is PrimaryGroupLayout) return true;
  if (node is GroupLayout) return false;
  return (node as SplitLayout).children.any(hasPrimaryGroupNode);
}

/// The layout tree as persisted groups plus a [PersistedEditorLayout] node.
///
/// [convert] is called once per group in layout order and the results are
/// numbered in that same order, so the flat list and the tree always agree.
/// Converting a group's tabs is the caller's job: it owns the file model, and
/// the tree only owns the shape.
({List<PersistedEditorGroup> groups, PersistedEditorLayout node})
persistEditorLayout(
  ProviderContainer container,
  PersistedEditorGroup Function(TabbedViewController controller) convert,
) {
  final groups = <PersistedEditorGroup>[];
  final node = _persistNode(
    container,
    container.read(editorLayoutProvider),
    groups,
    convert,
  );
  return (groups: groups, node: node);
}

PersistedEditorLayout _persistNode(
  ProviderContainer container,
  EditorLayout node,
  List<PersistedEditorGroup> groups,
  PersistedEditorGroup Function(TabbedViewController controller) convert,
) {
  if (node is! SplitLayout) {
    final index = groups.length;
    groups.add(convert(groupController(container, node)));
    return PersistedEditorLayout.group(index);
  }
  return PersistedEditorLayout.split(node.axis.name, [
    for (final child in node.children)
      _persistNode(container, child, groups, convert),
  ]);
}

/// Rebuilds the layout tree from [groups] and [node].
///
/// The primary provider owns group 0 so it stays where new files open; every
/// other group gets a fresh, empty controller. The callers seed those
/// controllers (the seeding is async, so it cannot happen here); the returned
/// [controllers] are the exact instances wired into [node], so the two stay in
/// sync. A node pointing past the groups that survived the restore is dropped,
/// so a session saved with tabs that have since been deleted still opens.
({EditorLayout node, List<TabbedViewController> controllers})
restoreEditorLayout(
  ProviderContainer container,
  List<PersistedEditorGroup> groups,
  PersistedEditorLayout? node,
) {
  final primary = container.read(tabbedViewControllerProvider);
  if (node == null || !node.isSplit || groups.isEmpty) {
    return (node: const PrimaryGroupLayout(), controllers: [primary]);
  }

  final controllers = <TabbedViewController>[primary];
  for (var i = 1; i < groups.length; i++) {
    controllers.add(TabbedViewController([]));
  }

  EditorLayout build(PersistedEditorLayout n) {
    if (!n.isSplit) {
      final index = (n.groupIndex ?? 0).clamp(0, controllers.length - 1);
      return index == 0
          ? const PrimaryGroupLayout()
          : GroupLayout(controllers[index]);
    }
    final children = <EditorLayout>[];
    for (final child in n.children) {
      if ((child.groupIndex ?? 0) >= controllers.length) continue;
      children.add(build(child));
    }
    if (children.isEmpty) return const PrimaryGroupLayout();
    if (children.length == 1) return children.single;
    return SplitLayout(
      n.axis == 'vertical' ? Axis.vertical : Axis.horizontal,
      children,
    );
  }

  return (node: build(node), controllers: controllers);
}

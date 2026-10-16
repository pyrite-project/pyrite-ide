import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
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

  // The tab the user was looking at in [from] must survive the move.
  final selected = from.selectedTab;
  from.removeTab(index);
  focused.insertTab(focused.tabs.length, tab);
  focused.selectTab(tab);
  if (selected != null && from.tabs.contains(selected)) {
    from.selectTab(selected);
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

  from.removeTab(index);
  into.insertTab(into.tabs.length, tab);
  into.selectTab(tab);
  container.read(focusedEditorGroupProvider.notifier).state = into;
  _refreshLayout(container);
  return true;
}

/// The group currently holding [tab], or null when it is not in the layout.
///
/// A tab does not have to be dragged within its own group: dropping it on
/// another group's edge has to know where it comes from to move it out.
TabbedViewController? holdingEditorGroup(
  ProviderContainer container,
  TabData tab,
) {
  for (final controller in allEditorControllers(container)) {
    if (controller.tabs.contains(tab)) return controller;
  }
  return null;
}

/// Whether dropping [tab] on [target]'s edge would really split.
///
/// Asked twice: once to decide whether to show the drop preview, and once
/// again on the drop itself. Showing a preview the drop cannot honour is what
/// used to make a split look accepted and then silently do nothing.
bool canSplitEditorGroup(
  ProviderContainer container, {
  required TabbedViewController target,
  required TabData tab,
}) {
  final from = holdingEditorGroup(container, tab);
  if (from == null) return false;
  // Splitting a group's own last tab would empty it, and pruning would then
  // undo the split -- refuse it rather than pretend it happened.
  return !identical(from, target) || from.tabs.length >= 2;
}

/// Splits the group [target] towards [where] and moves [tab] into the new one.
///
/// [tab] comes from wherever it currently is, which need not be [target]:
/// dragging across groups onto an edge is the usual way to open a new group.
bool splitEditorGroup(
  ProviderContainer container, {
  required TabbedViewController target,
  required TabData tab,
  required EditorSplit where,
}) {
  final from = holdingEditorGroup(container, tab);
  if (from == null) return false;
  if (identical(from, target) && from.tabs.length < 2) return false;

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
}

/// The layout as it should be: empty groups dropped, primary brought back.
EditorLayout refreshEditorLayout(ProviderContainer container) {
  final primary = container.read(tabbedViewControllerProvider);
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

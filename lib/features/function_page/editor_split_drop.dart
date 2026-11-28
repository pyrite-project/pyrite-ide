import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/shared/tabbed_view/native_tab_drag.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// Share of a group's size that counts as its edge, as in VS Code: the outer
/// 10% of each dimension splits the group, the inner 80%x80% moves the tab
/// into it. Proportional, so a small group offers the same gesture a large one
/// does, and no pane is ever small enough for the bands to cover it all.
const double _splitEdgeRatio = 0.1;

/// Width of the strip, measured from the editor area's boundary, that splits
/// the area itself instead of the group it runs along.
///
/// Every ancestor group has its edges covered by its children's, so without
/// this strip a second split above the top-level one has no gesture at all.
/// Wide enough to find without aiming for it, while still leaving most of the
/// edge band to the group's own split -- and never more than half of it, so a
/// small group's band still reaches its own split.
const double _areaEdgeExtent = 40;

/// The area-level split a drop is currently promising, or null.
///
/// The root of the layout has no pane of its own, so the preview for a
/// root-level split has to be drawn by the editor area rather than by the
/// region the pointer is over -- which is a leaf and only covers part of what
/// the split will take.
final StateProvider<PaneEdge?> editorAreaSplitPreviewProvider =
    StateProvider<PaneEdge?>((ref) => null);

/// Where, and at which level, a drop would split.
typedef _PendingSplit = ({PaneEdge where, bool root});

/// Drop target of one group.
///
/// The zones are VS Code's: the outer 10% of each dimension splits *this*
/// group -- which is what makes splits nest: the new group is a leaf of the
/// same tree, so it can be split again -- and the inner 80%x80% moves the tab
/// into this group. Side-by-side splits are preferred there, so the outer
/// thirds of the width decide first and only the middle third splits up or
/// down, corners included.
///
/// The outermost [_areaEdgeExtent] of an edge the group shares with the editor
/// area's boundary splits the area itself, which is how a second split above
/// the top-level one is made.
///
/// A group that lives outside the editor layout -- the docked console panel --
/// passes [edgeTarget], the editor group its edge drops split instead.
class EditorSplitDropRegion extends ConsumerStatefulWidget {
  const EditorSplitDropRegion({
    super.key,
    required this.controller,
    required this.child,
    this.edgeTarget,
    this.accept,
  });

  /// The group this region stands for.
  final TabbedViewController controller;

  final Widget child;

  /// The group an edge drop splits when [controller] is not in the editor tree.
  final TabbedViewController? edgeTarget;

  /// Extra gate on the dragged tab.
  ///
  /// A document dropped into a group that is not a node of the editor layout
  /// would live where nothing else can see it: persistence, the unsaved guard
  /// and the open-file dedup all walk the tree only. The console panel takes
  /// back only the surfaces it created.
  final bool Function(TabData tab)? accept;

  @override
  ConsumerState<EditorSplitDropRegion> createState() =>
      _EditorSplitDropRegionState();
}

class _EditorSplitDropRegionState extends ConsumerState<EditorSplitDropRegion> {
  _PendingSplit? _pending;

  /// The group an edge drop splits.
  ///
  /// The console panel is a group that is not a node of the editor layout, so
  /// splitting it in place would strand the new group outside the tree: its
  /// edge drops split the editor group it names instead.
  TabbedViewController? get _splitTarget {
    if (ref.read(editorLayoutProvider).contains(widget.controller)) {
      return widget.controller;
    }
    return widget.edgeTarget;
  }

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      // Like the tab regions: the payload is local, so no format has to be
      // declared for the native side to route the session here.
      formats: const [],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropLeave: (_) => _clearPending(),
      onDropEnded: (_) => _clearPending(),
      onPerformDrop: _onPerformDrop,
      child: Stack(
        children: [
          widget.child,
          // A root-level split takes regions this leaf only partly covers, so
          // the editor area draws that preview; see [editorAreaSplitPreviewProvider].
          if (_pending != null && !_pending!.root)
            Positioned.fill(child: EditorSplitHint(split: _pending!.where)),
        ],
      ),
    );
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final registration = NativeTabDragRegistry.registrationForSession(
      event.session,
    );
    final source = registration?.source;
    if (source == null) {
      _clearPending();
      return DropOperation.none;
    }
    if (widget.accept != null && !widget.accept!(source.tab)) {
      _clearPending();
      return DropOperation.none;
    }
    // Only preview a split the drop can actually honour.
    final split = _resolveSplit(event.position.local);
    final canSplit = split != null && _canSplit(source, split);
    _setPending(canSplit ? split : null);
    // Accept anywhere in the pane: outside the edge bands the tab just moves
    // into this group, the way VS Code treats a drop on an editor's body.
    return DropOperation.move;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final registration = NativeTabDragRegistry.registrationForSession(
      event.session,
    );
    final source = registration?.source;
    final split = _resolveSplit(event.position.local);
    _clearPending();
    if (source == null) return;
    if (widget.accept != null && !widget.accept!(source.tab)) return;

    // Claim the session so the strip's trend fallback does not also move it.
    registration!.dropHandled = true;
    final layout = ref.read(editorLayoutProvider.notifier);
    if (split != null && split.root) {
      layout.splitArea(
        from: source.controller,
        tab: source.tab,
        where: split.where,
      );
      return;
    }
    final splitTarget = split == null ? null : _splitTarget;
    if (splitTarget == null || split == null) {
      layout.moveTab(
        from: source.controller,
        tab: source.tab,
        into: widget.controller,
      );
      return;
    }
    layout.splitGroup(
      from: source.controller,
      target: splitTarget,
      tab: source.tab,
      where: split.where,
    );
  }

  bool _canSplit(NativeTabDragSource source, _PendingSplit split) {
    final layout = ref.read(editorLayoutProvider.notifier);
    if (split.root) {
      return layout.canSplitArea(from: source.controller, tab: source.tab);
    }
    final splitTarget = _splitTarget;
    if (splitTarget == null) return false;
    return layout.canSplitGroup(
      from: source.controller,
      target: splitTarget,
      tab: source.tab,
    );
  }

  /// Which edge [local] falls on and at which level, or null when the drop is
  /// in the group's middle, which moves the tab into it.
  ///
  /// VS Code's zones: a drop inside the inner 80% of both axes merges; outside
  /// it, the outer thirds of the width split left or right -- side-by-side is
  /// the preferred direction, so the corners go with them -- and the middle
  /// third's top and bottom bands split up or down.
  _PendingSplit? _resolveSplit(Offset local) {
    final size = context.size;
    if (size == null) return null;
    final width = size.width;
    final height = size.height;
    final edgeWidth = width * _splitEdgeRatio;
    final edgeHeight = height * _splitEdgeRatio;
    if (local.dx > edgeWidth &&
        local.dx < width - edgeWidth &&
        local.dy > edgeHeight &&
        local.dy < height - edgeHeight) {
      return null;
    }
    final splitWidth = width / 3;
    if (local.dx < splitWidth) {
      return _pendingSplit(PaneEdge.left, local.dx, edgeWidth);
    }
    if (local.dx > splitWidth * 2) {
      return _pendingSplit(PaneEdge.right, width - local.dx, edgeWidth);
    }
    return local.dy < height / 2
        ? _pendingSplit(PaneEdge.top, local.dy, edgeHeight)
        : _pendingSplit(PaneEdge.bottom, height - local.dy, edgeHeight);
  }

  /// A drop [depth] into the [band] of [where]: root-level when the group sits
  /// on the area's boundary and the drop is in the outermost strip, the group
  /// itself otherwise.
  _PendingSplit _pendingSplit(PaneEdge where, double depth, double band) {
    final areaExtent = math.min(_areaEdgeExtent, band / 2);
    final atBoundary =
        depth <= areaExtent &&
        ref
            .read(editorLayoutProvider.notifier)
            .isAtAreaEdge(widget.controller, where);
    return (where: where, root: atBoundary);
  }

  void _setPending(_PendingSplit? split) {
    if (_pending == split) return;
    if (!mounted) return;
    setState(() => _pending = split);
    _syncAreaPreview(split);
  }

  void _clearPending() {
    if (_pending == null) return;
    if (!mounted) return;
    setState(() => _pending = null);
    _syncAreaPreview(null);
  }

  /// Publishes the area-level half of the preview; the leaf-level half stays
  /// local to the region that promised it.
  void _syncAreaPreview(_PendingSplit? split) {
    final rootSplit = split?.root == true ? split?.where : null;
    if (ref.read(editorAreaSplitPreviewProvider) == rootSplit) return;
    ref.read(editorAreaSplitPreviewProvider.notifier).state = rootSplit;
  }
}

/// Translucent preview of the group a drop would create.
///
/// Deliberately just a rectangle: VS Code shows where the split lands and
/// nothing else. It is drawn over whatever the split will take -- a leaf's
/// region for a leaf split, the editor area for a root-level one -- at the
/// [newEditorGroupShare] the new group then gets.
class EditorSplitHint extends StatelessWidget {
  const EditorSplitHint({super.key, required this.split});

  final PaneEdge split;

  AlignmentGeometry get alignment => switch (split) {
    PaneEdge.left => Alignment.centerLeft,
    PaneEdge.top => Alignment.topCenter,
    PaneEdge.right => Alignment.centerRight,
    PaneEdge.bottom => Alignment.bottomCenter,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: FractionallySizedBox(
          widthFactor: split.axis == Axis.horizontal ? newEditorGroupShare : 1,
          heightFactor: split.axis == Axis.vertical ? newEditorGroupShare : 1,
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.28),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.8)),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/shared/tabbed_view/native_tab_drag.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// Width of the band along each edge that splits the group.
const double _splitEdgeExtent = 96;

/// Smallest area that still offers a split: below this the bands would cover
/// the whole pane and every drop would hit one.
const Size _splitMinimumArea = Size(360, 240);

/// Drop target of one editor group.
///
/// Dropping near an edge splits *this* group — which is what makes splits nest:
/// the new group is a leaf of the same tree, so it can be split again. Dropping
/// in the middle moves the tab into this group, the way VS Code does.
///
/// [target] is the layout node, not a controller: the primary group resolves
/// its controller per read because the tab controller is swapped underneath it.
class EditorSplitDropRegion extends ConsumerStatefulWidget {
  const EditorSplitDropRegion({
    super.key,
    required this.target,
    required this.child,
  });

  final EditorLayout target;
  final Widget child;

  @override
  ConsumerState<EditorSplitDropRegion> createState() =>
      _EditorSplitDropRegionState();
}

class _EditorSplitDropRegionState extends ConsumerState<EditorSplitDropRegion> {
  EditorSplit? _pending;

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
          if (_pending != null)
            Positioned.fill(child: _EditorSplitHint(split: _pending!)),
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
    // Only preview a split the drop can actually honour.
    final split = _resolveSplit(event.position.local);
    _setPending(split != null && _canSplit(source.tab) ? split : null);
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

    // Claim the session so the strip's trend fallback does not also move it.
    registration!.dropHandled = true;
    final container = ProviderScope.containerOf(context);
    if (split == null) {
      moveTabToEditorGroup(
        container,
        from: source.controller,
        tab: source.tab,
        into: _targetController,
      );
      return;
    }
    splitEditorGroup(
      container,
      target: _targetController,
      tab: source.tab,
      where: split,
    );
  }

  bool _canSplit(TabData tab) {
    return canSplitEditorGroup(
      ProviderScope.containerOf(context),
      target: _targetController,
      tab: tab,
    );
  }

  TabbedViewController get _targetController =>
      groupController(ProviderScope.containerOf(context), widget.target);

  /// Which edge [local] falls on, or null when it is not near one.
  EditorSplit? _resolveSplit(Offset local) {
    final size = context.size;
    if (size == null) return null;
    if (size.width < _splitMinimumArea.width ||
        size.height < _splitMinimumArea.height) {
      return null;
    }
    if (local.dx <= _splitEdgeExtent) return EditorSplit.left;
    if (local.dx >= size.width - _splitEdgeExtent) return EditorSplit.right;
    if (local.dy <= _splitEdgeExtent) return EditorSplit.top;
    if (local.dy >= size.height - _splitEdgeExtent) return EditorSplit.bottom;
    return null;
  }

  void _setPending(EditorSplit? split) {
    if (_pending == split) return;
    if (!mounted) return;
    setState(() => _pending = split);
  }

  void _clearPending() {
    if (_pending == null) return;
    if (!mounted) return;
    setState(() => _pending = null);
  }
}

/// Translucent preview of the group a drop would create.
///
/// Deliberately just a rectangle: VS Code shows where the split lands and
/// nothing else.
class _EditorSplitHint extends StatelessWidget {
  const _EditorSplitHint({required this.split});

  final EditorSplit split;

  AlignmentGeometry get alignment => switch (split) {
    EditorSplit.left => Alignment.centerLeft,
    EditorSplit.top => Alignment.topCenter,
    EditorSplit.right => Alignment.centerRight,
    EditorSplit.bottom => Alignment.bottomCenter,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: FractionallySizedBox(
          widthFactor: split.axis == Axis.horizontal ? 0.4 : 1,
          heightFactor: split.axis == Axis.vertical ? 0.4 : 1,
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

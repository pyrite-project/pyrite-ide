import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pyrite_ide/core/sdk/tree_index.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';

/// Virtualized tree for plugin views, driven by [TreeIndex].
///
/// Only the visible window is built, so a tree can describe far more logical
/// nodes than it materializes. Expansion splices the affected rows in the index
/// rather than re-flattening, and a label change repaints one row.
class PluginTreeView extends StatefulWidget {
  const PluginTreeView({
    super.key,
    required this.index,
    this.selectedId,
    this.indent = 16,
    this.rowHeight = 24,
    this.emptyLabel,
    this.onSelect,
    this.onActivate,
    this.onExpand,
    this.onCollapse,
    this.onRequestChildren,
    this.onContextMenu,
    this.contextMenuBuilder,
    this.contentBuilder,
  });

  final TreeIndex index;
  final String? selectedId;
  final double indent;
  final double rowHeight;
  final String? emptyLabel;

  final void Function(String nodeId)? onSelect;
  final void Function(String nodeId)? onActivate;
  final void Function(String nodeId)? onExpand;
  final void Function(String nodeId)? onCollapse;
  final void Function(String nodeId)? onRequestChildren;
  final void Function(String nodeId, Offset globalPosition)? onContextMenu;
  final Widget Function(Widget child, String nodeId)? contextMenuBuilder;
  final Widget Function(BuildContext context, TreeNodeModel model)?
  contentBuilder;

  @override
  State<PluginTreeView> createState() => PluginTreeViewState();
}

class PluginTreeViewState extends State<PluginTreeView> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// Rows built since the last reset, for rebuild-count assertions in tests.
  int builtRowCount = 0;

  String? _selectedId;
  DateTime? _lastTap;
  String? _lastTapNodeId;

  String? get selectedId => _selectedId;

  bool selectNode(String nodeId) {
    if (widget.index.node(nodeId) == null) return false;
    _select(nodeId);
    return true;
  }

  void clearSelection() => setState(() => _selectedId = null);

  bool expandNode(String nodeId) {
    if (widget.index.node(nodeId) == null) return false;
    _expand(nodeId);
    return true;
  }

  bool collapseNode(String nodeId) {
    if (widget.index.node(nodeId) == null) return false;
    _collapse(nodeId);
    return true;
  }

  bool toggleNode(String nodeId) {
    if (widget.index.node(nodeId) == null) return false;
    _toggle(nodeId);
    return true;
  }

  void expandAll() {
    for (final id in widget.index.nodeById.keys) {
      if (widget.index.node(id)?.hasChildren == true &&
          !widget.index.needsChildren(id)) {
        widget.index.expand(id);
      }
    }
    refresh();
  }

  void collapseAll() {
    for (final id in List<String>.from(widget.index.expandedNodeIds)) {
      widget.index.collapse(id);
    }
    refresh();
  }

  Future<bool> revealNode(String nodeId, {bool animated = true}) async {
    var current = widget.index.node(nodeId);
    if (current == null) return false;
    final parents = <String>[];
    while (current?.parentId != null) {
      parents.add(current!.parentId!);
      current = widget.index.node(current.parentId!);
    }
    for (final parent in parents.reversed) {
      widget.index.expand(parent);
    }
    refresh();
    await WidgetsBinding.instance.endOfFrame;
    final index = widget.index.visibleIndexOf(nodeId);
    if (index == null || !_scrollController.hasClients) return false;
    final target = (index * widget.rowHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    if (animated) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
    return true;
  }

  List<String> get visibleNodeIds =>
      List.unmodifiable(widget.index.visibleNodeIds);

  /// Repaints after the caller mutated [PluginTreeView.index] directly.
  ///
  /// The index is host-owned and mutable (that is what makes a relabel cost one
  /// row instead of a rebuild), so whoever mutates it asks for the repaint.
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  void didUpdateWidget(PluginTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A plugin-driven selection change wins; otherwise keep the local one so
    // selection survives model updates.
    if (widget.selectedId != oldWidget.selectedId) {
      _selectedId = widget.selectedId;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _select(String nodeId) {
    // Clicking a row takes keyboard focus, so arrow keys continue from there.
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    setState(() => _selectedId = nodeId);
    widget.onSelect?.call(nodeId);
  }

  /// Selection fires on the first tap; a quick second tap adds activate, so
  /// selection never waits for the double-tap timeout.
  void _tapRow(String nodeId) {
    final now = DateTime.now();
    final isDouble =
        _lastTapNodeId == nodeId &&
        _lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 300);
    _lastTap = now;
    _lastTapNodeId = nodeId;
    _select(nodeId);
    if (isDouble) {
      _lastTap = null;
      widget.onActivate?.call(nodeId);
    }
  }

  /// Expands a node, requesting children first when they are not loaded.
  void _expand(String nodeId) {
    if (widget.index.needsChildren(nodeId)) {
      widget.index.markExpanded(nodeId);
      widget.index.setChildrenState(nodeId, ChildrenState.loading);
      setState(() {});
      widget.onRequestChildren?.call(nodeId);
      return;
    }
    setState(() => widget.index.expand(nodeId));
    widget.onExpand?.call(nodeId);
  }

  void _collapse(String nodeId) {
    setState(() => widget.index.collapse(nodeId));
    widget.onCollapse?.call(nodeId);
  }

  void _toggle(String nodeId) {
    if (widget.index.isExpanded(nodeId)) {
      _collapse(nodeId);
    } else {
      _expand(nodeId);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final visible = widget.index.visibleNodeIds;
    if (visible.isEmpty) return KeyEventResult.ignored;
    final current = selectedId;
    final at = current == null
        ? -1
        : widget.index.visibleIndexOf(current) ?? -1;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        final next = (at + 1).clamp(0, visible.length - 1);
        _select(visible[next]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        final next = at <= 0 ? 0 : at - 1;
        _select(visible[next]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (current == null) return KeyEventResult.ignored;
        final model = widget.index.node(current);
        if (model != null &&
            model.hasChildren &&
            !widget.index.isExpanded(current)) {
          _expand(current);
        } else if (at + 1 < visible.length) {
          _select(visible[at + 1]);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (current == null) return KeyEventResult.ignored;
        if (widget.index.isExpanded(current)) {
          _collapse(current);
        } else {
          final parentId = widget.index.node(current)?.parentId;
          if (parentId != null) _select(parentId);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (current != null) widget.onActivate?.call(current);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _select(visible.first);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _select(visible.last);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.index.visibleNodeIds;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          widget.emptyLabel ?? 'Nothing to show',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded = constraints.hasBoundedHeight;
          return ListView.builder(
            controller: _scrollController,
            itemCount: visible.length,
            itemExtent: widget.rowHeight,
            shrinkWrap: !bounded,
            physics: bounded ? null : const NeverScrollableScrollPhysics(),
            itemBuilder: (context, position) =>
                _buildRow(context, visible[position]),
          );
        },
      ),
    );
  }

  Widget _buildRow(BuildContext context, String nodeId) {
    builtRowCount++;
    final model = widget.index.node(nodeId);
    if (model == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final expanded = widget.index.isExpanded(nodeId);
    final depth = widget.index.depthOf(nodeId);
    final selected = nodeId == selectedId;

    final row = InkWell(
      onTap: () => _tapRow(nodeId),
      onSecondaryTapDown: widget.onContextMenu == null
          ? null
          : (details) => widget.onContextMenu!(nodeId, details.globalPosition),
      child: ColoredBox(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(left: 4 + depth * widget.indent, right: 4),
          child: Row(
            children: [
              _leading(model, expanded, scheme),
              if (model.icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    _icon(model.icon!),
                    size: 14,
                    color: _iconColor(
                      scheme,
                      model.data['iconColor']?.toString(),
                    ),
                  ),
                ),
              Expanded(
                child:
                    widget.contentBuilder?.call(context, model) ??
                    Text(
                      model.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
              ),
              if (model.childrenState == ChildrenState.error)
                Tooltip(
                  message: 'Failed to load children; click to retry',
                  child: InkWell(
                    onTap: () {
                      widget.index.setChildrenState(
                        nodeId,
                        ChildrenState.unloaded,
                      );
                      _expand(nodeId);
                    },
                    child: Icon(
                      Icons.error_outline,
                      size: 14,
                      color: scheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return widget.contextMenuBuilder?.call(row, nodeId) ?? row;
  }

  /// Expand affordance, or a spinner while children load.
  Widget _leading(TreeNodeModel model, bool expanded, ColorScheme scheme) {
    if (model.childrenState == ChildrenState.loading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }
    if (!model.hasChildren) return const SizedBox(width: 16);
    return InkWell(
      onTap: () => _toggle(model.id),
      child: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 16),
    );
  }

  IconData _icon(String reference) => pluginIcon(reference);

  Color _iconColor(ColorScheme scheme, String? token) => switch (token) {
    'primary' => scheme.primary,
    'secondary' => scheme.secondary,
    'tertiary' => scheme.tertiary,
    'error' => scheme.error,
    'muted' => scheme.onSurfaceVariant,
    _ => scheme.onSurfaceVariant,
  };
}

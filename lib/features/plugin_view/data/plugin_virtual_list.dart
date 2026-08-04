import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pyrite_ide/features/plugin_view/data/visible_range_tracker.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';

/// Virtualized flat list for plugin views.
///
/// [itemCount] may exceed the number of loaded [items]: gaps render as
/// placeholders and trigger a coalesced `requestRange` rather than a round-trip
/// per scrolled frame. A fixed [itemExtent] keeps scrolling O(visible rows).
class PluginVirtualList extends StatefulWidget {
  const PluginVirtualList({
    super.key,
    required this.items,
    required this.itemCount,
    this.itemExtent = 22,
    this.selectedId,
    this.emptyLabel,
    this.onSelect,
    this.onActivate,
    this.onRequestRange,
    this.contextMenuBuilder,
  });

  /// Loaded rows keyed by absolute index, so a sparse window works.
  final Map<int, Map<String, dynamic>> items;
  final int itemCount;
  final double itemExtent;
  final String? selectedId;
  final String? emptyLabel;

  final void Function(String itemId)? onSelect;
  final void Function(String itemId)? onActivate;
  final void Function(int start, int count)? onRequestRange;
  final Widget Function(Widget child, String itemId)? contextMenuBuilder;

  @override
  State<PluginVirtualList> createState() => PluginVirtualListState();
}

class PluginVirtualListState extends State<PluginVirtualList> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final VisibleRangeTracker _tracker = VisibleRangeTracker(
    onRequest: (start, count) => widget.onRequestRange?.call(start, count),
  );

  /// Rows built since the last reset, for rebuild-count assertions in tests.
  int builtRowCount = 0;

  String? _selectedId;
  int _selectedIndex = -1;
  DateTime? _lastTap;
  String? _lastTapItemId;

  String? get selectedId => _selectedId;

  bool selectItem(String itemId) {
    for (final entry in widget.items.entries) {
      if ((entry.value['id']?.toString() ?? '${entry.key}') == itemId) {
        _select(entry.key, itemId);
        return true;
      }
    }
    return false;
  }

  void clearSelection() => setState(() {
    _selectedId = null;
    _selectedIndex = -1;
  });

  Future<bool> revealItem(String itemId, {bool animated = true}) async {
    for (final entry in widget.items.entries) {
      if ((entry.value['id']?.toString() ?? '${entry.key}') == itemId) {
        await scrollToIndex(entry.key, animated: animated);
        return true;
      }
    }
    return false;
  }

  Future<void> scrollToIndex(int index, {bool animated = true}) async {
    if (!_scrollController.hasClients || widget.itemCount == 0) return;
    final target = (index.clamp(0, widget.itemCount - 1) * widget.itemExtent)
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
  }

  Future<void> scrollBy(double delta, {bool animated = true}) async {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (animated) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  Map<String, int> get visibleRange {
    if (!_scrollController.hasClients || widget.itemCount == 0) {
      return const {'start': 0, 'count': 0};
    }
    final start = (_scrollController.offset / widget.itemExtent).floor();
    final end =
        ((_scrollController.offset +
                    _scrollController.position.viewportDimension) /
                widget.itemExtent)
            .ceil()
            .clamp(start, widget.itemCount);
    return {'start': start, 'count': end - start};
  }

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  void didUpdateWidget(PluginVirtualList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId != oldWidget.selectedId) {
      _selectedId = widget.selectedId;
    }
  }

  @override
  void dispose() {
    _tracker.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _select(int index, String itemId) {
    // Clicking a row takes keyboard focus, so arrow keys continue from there.
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    setState(() {
      _selectedId = itemId;
      _selectedIndex = index;
    });
    widget.onSelect?.call(itemId);
  }

  void _tapRow(int index, String itemId) {
    final now = DateTime.now();
    final isDouble =
        _lastTapItemId == itemId &&
        _lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 300);
    _lastTap = now;
    _lastTapItemId = itemId;
    _select(index, itemId);
    if (isDouble) {
      _lastTap = null;
      widget.onActivate?.call(itemId);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.itemCount == 0) return KeyEventResult.ignored;

    int? target;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        target = (_selectedIndex + 1).clamp(0, widget.itemCount - 1);
      case LogicalKeyboardKey.arrowUp:
        target = _selectedIndex <= 0 ? 0 : _selectedIndex - 1;
      case LogicalKeyboardKey.home:
        target = 0;
      case LogicalKeyboardKey.end:
        target = widget.itemCount - 1;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        final current = selectedId;
        if (current != null) widget.onActivate?.call(current);
        return KeyEventResult.handled;
    }
    if (target == null) return KeyEventResult.ignored;
    final item = widget.items[target];
    if (item == null) {
      // Keyboard moved into an unloaded gap; ask for it and stop here.
      _tracker.noteMissing(target, target + 1);
      return KeyEventResult.handled;
    }
    _select(target, item['id']?.toString() ?? '$target');
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
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
            itemCount: widget.itemCount,
            itemExtent: widget.itemExtent,
            shrinkWrap: !bounded,
            physics: bounded ? null : const NeverScrollableScrollPhysics(),
            itemBuilder: _buildRow,
          );
        },
      ),
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final item = widget.items[index];
    if (item == null) {
      _tracker.noteMissing(index, index + 1);
      return _placeholder(context);
    }
    builtRowCount++;
    final itemId = item['id']?.toString() ?? '$index';
    final selected = itemId == selectedId;
    final scheme = Theme.of(context).colorScheme;

    final row = InkWell(
      onTap: () => _tapRow(index, itemId),
      child: ColoredBox(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              if (item['icon'] != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(_icon(item['icon'].toString()), size: 14),
                ),
              Expanded(
                child: Text(
                  item['label']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return widget.contextMenuBuilder?.call(row, itemId) ?? row;
  }

  Widget _placeholder(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(2),
      ),
      child: const SizedBox(height: 8, width: double.infinity),
    ),
  );

  IconData _icon(String reference) => pluginIcon(reference);
}

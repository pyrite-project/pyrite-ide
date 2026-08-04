import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_table_view/material_table_view.dart';
import 'package:material_table_view/table_view_typedefs.dart';
import 'package:pyrite_ide/features/plugin_view/data/visible_range_tracker.dart';

/// A stable column definition supplied by a plugin.
class PluginColumn {
  const PluginColumn({
    required this.id,
    required this.label,
    this.width = 120,
    this.flex = 0,
    this.frozen = false,
    this.sortable = true,
  });

  factory PluginColumn.fromJson(Map<String, dynamic> json) => PluginColumn(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    width: (json['width'] as num?)?.toDouble() ?? 120,
    flex: (json['flex'] as num?)?.toInt() ?? 0,
    frozen: json['frozen'] == true,
    sortable: json['sortable'] != false,
  );

  final String id;
  final String label;
  final double width;
  final int flex;
  final bool frozen;
  final bool sortable;
}

/// Virtualized table for plugin views.
///
/// Rows are built on demand by `material_table_view`, so a table can describe
/// far more rows than it materializes. [rowCount] may exceed the number of
/// loaded [rows]; the gaps render as placeholders and trigger a coalesced
/// `requestRange` instead of a per-frame round-trip.
class PluginDataTable extends StatefulWidget {
  const PluginDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowCount,
    this.rowHeight = 28,
    this.showHeader = true,
    this.selectedId,
    this.sortColumn,
    this.sortAscending = true,
    this.emptyLabel,
    this.onSelect,
    this.onActivate,
    this.onSort,
    this.onRequestRange,
    this.contextMenuBuilder,
  });

  final List<PluginColumn> columns;

  /// Loaded rows keyed by their absolute index, so a sparse window works.
  final Map<int, Map<String, dynamic>> rows;
  final int rowCount;
  final double rowHeight;
  final bool showHeader;
  final String? selectedId;
  final String? sortColumn;
  final bool sortAscending;
  final String? emptyLabel;

  final void Function(String rowId)? onSelect;
  final void Function(String rowId)? onActivate;
  final void Function(String columnId)? onSort;
  final void Function(int start, int count)? onRequestRange;
  final Widget Function(Widget child, String rowId)? contextMenuBuilder;

  @override
  State<PluginDataTable> createState() => PluginDataTableState();
}

class PluginDataTableState extends State<PluginDataTable> {
  final FocusNode _focusNode = FocusNode();
  final TableViewController tableController = TableViewController();
  late final VisibleRangeTracker _tracker = VisibleRangeTracker(
    onRequest: (start, count) => widget.onRequestRange?.call(start, count),
  );
  String? _selectedRowId;

  /// Rows built since the last reset, for the rebuild-count assertions in tests.
  int builtRowCount = 0;

  DateTime? _lastTap;
  String? _lastTapRowId;

  bool selectRow(String rowId) {
    for (final entry in widget.rows.entries) {
      if (_rowId(entry.key, entry.value) == rowId) {
        _selectIndex(entry.key);
        return true;
      }
    }
    return false;
  }

  void clearSelection() => setState(() => _selectedRowId = null);

  Future<bool> revealRow(String rowId, {bool animated = true}) async {
    for (final entry in widget.rows.entries) {
      if (_rowId(entry.key, entry.value) == rowId) {
        await scrollToRow(entry.key, animated: animated);
        return true;
      }
    }
    return false;
  }

  Future<void> scrollToRow(int row, {bool animated = true}) async {
    final controller = tableController.verticalScrollController;
    if (!controller.hasClients || widget.rowCount == 0) return;
    final target = (row.clamp(0, widget.rowCount - 1) * widget.rowHeight)
        .clamp(0.0, controller.position.maxScrollExtent)
        .toDouble();
    if (animated) {
      await controller.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      controller.jumpTo(target);
    }
  }

  Future<bool> revealCell(
    String rowId,
    String columnId, {
    bool animated = true,
  }) async {
    final rowFound = await revealRow(rowId, animated: animated);
    final column = widget.columns.indexWhere((value) => value.id == columnId);
    if (!rowFound || column < 0) return false;
    final controller = tableController.horizontalScrollController;
    if (!controller.hasClients) return true;
    var offset = 0.0;
    for (var index = 0; index < column; index++) {
      offset += widget.columns[index].width;
    }
    final target = offset.clamp(0.0, controller.position.maxScrollExtent);
    if (animated) {
      await controller.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      controller.jumpTo(target);
    }
    return true;
  }

  Map<String, int> get visibleRange {
    final controller = tableController.verticalScrollController;
    if (!controller.hasClients || widget.rowCount == 0) {
      return const {'start': 0, 'count': 0};
    }
    final start = (controller.offset / widget.rowHeight).floor();
    final end =
        ((controller.offset + controller.position.viewportDimension) /
                widget.rowHeight)
            .ceil()
            .clamp(start, widget.rowCount);
    return {'start': start, 'count': end - start};
  }

  @override
  void initState() {
    super.initState();
    _selectedRowId = widget.selectedId;
  }

  @override
  void didUpdateWidget(covariant PluginDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId &&
        widget.selectedId != _selectedRowId) {
      _selectedRowId = widget.selectedId;
    }
  }

  @override
  void dispose() {
    _tracker.dispose();
    _focusNode.dispose();
    tableController.dispose();
    super.dispose();
  }

  /// Selection fires on the first tap; a quick second tap adds activate, so
  /// selecting never waits for a double-tap timeout.
  void _tapRow(String rowId) {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    final now = DateTime.now();
    final isDouble =
        _lastTapRowId == rowId &&
        _lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 300);
    _lastTap = now;
    _lastTapRowId = rowId;
    setState(() => _selectedRowId = rowId);
    widget.onSelect?.call(rowId);
    if (isDouble) {
      _lastTap = null;
      widget.onActivate?.call(rowId);
    }
  }

  String _rowId(int index, Map<String, dynamic> row) =>
      row['id']?.toString() ?? '$index';

  int? get _selectedIndex {
    final selected = _selectedRowId;
    if (selected == null) return null;
    for (final entry in widget.rows.entries) {
      if (_rowId(entry.key, entry.value) == selected) return entry.key;
    }
    return null;
  }

  void _selectIndex(int index) {
    final row = widget.rows[index];
    if (row == null) {
      _tracker.noteMissing(index, index + 1);
      return;
    }
    final rowId = _rowId(index, row);
    setState(() => _selectedRowId = rowId);
    widget.onSelect?.call(rowId);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.rowCount == 0) {
      return KeyEventResult.ignored;
    }
    final current = _selectedIndex;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _selectIndex(((current ?? -1) + 1).clamp(0, widget.rowCount - 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _selectIndex(((current ?? 1) - 1).clamp(0, widget.rowCount - 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _selectIndex(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _selectIndex(widget.rowCount - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        final index = current;
        final row = index == null ? null : widget.rows[index];
        if (index != null && row != null) {
          widget.onActivate?.call(_rowId(index, row));
        }
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rowCount == 0) {
      return Center(
        child: Text(
          widget.emptyLabel ?? 'No rows',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: TableView.builder(
        controller: tableController,
        columns: [
          for (final column in widget.columns)
            TableColumn(
              width: column.width,
              flex: column.flex,
              freezePriority: column.frozen ? 1 : 0,
            ),
        ],
        rowCount: widget.rowCount,
        rowHeight: widget.rowHeight,
        headerBuilder: widget.showHeader ? _buildHeader : null,
        rowBuilder: _buildRow,
        placeholderRowBuilder: _buildPlaceholderRow,
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TableRowContentBuilder content) =>
      content(context, (context, columnIndex) {
        final column = widget.columns[columnIndex];
        final isSorted = column.id == widget.sortColumn;
        return InkWell(
          onTap: column.sortable ? () => widget.onSort?.call(column.id) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    column.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                if (isSorted)
                  Icon(
                    widget.sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 12,
                  ),
              ],
            ),
          ),
        );
      });

  /// Returns null for rows that are not loaded, which makes the table render a
  /// placeholder instead of blocking on data.
  Widget? _buildRow(
    BuildContext context,
    int row,
    TableRowContentBuilder content,
  ) {
    final data = widget.rows[row];
    if (data == null) {
      // Ask for the surrounding chunk; the tracker debounces and de-dupes.
      _tracker.noteMissing(row, row + 1);
      return null;
    }
    builtRowCount++;
    final rowId = _rowId(row, data);
    final selected = rowId == _selectedRowId;
    final cells = data['cells'];
    final rowWidget = InkWell(
      onTap: () => _tapRow(rowId),
      child: ColoredBox(
        color: selected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.4)
            : Colors.transparent,
        child: content(context, (context, columnIndex) {
          final column = widget.columns[columnIndex];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                cells is Map ? cells[column.id]?.toString() ?? '' : '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        }),
      ),
    );
    return widget.contextMenuBuilder?.call(rowWidget, rowId) ?? rowWidget;
  }

  Widget? _buildPlaceholderRow(
    BuildContext context,
    int row,
    TableRowContentBuilder content,
  ) => content(context, (context, columnIndex) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(2),
        ),
        child: const SizedBox(height: 8, width: double.infinity),
      ),
    );
  });
}

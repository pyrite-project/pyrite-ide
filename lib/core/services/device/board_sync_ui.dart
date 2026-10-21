import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';

// ---------------------------------------------------------------------------
// Board sync UI
//
// These widgets live in the device service layer rather than in the file page
// so they can be pumped in widget tests without importing the whole application
// shell (routes, settings pages, plugin registry). The file page only imports
// them.
// ---------------------------------------------------------------------------

/// Result the sync preview dialog returns to the file page.
class BoardSyncPreviewResult {
  const BoardSyncPreviewResult({
    required this.selectedPaths,
    this.direction = BoardSyncDirection.none,
  });

  /// Relative paths the user left checked.
  final Set<String> selectedPaths;

  /// Direction chosen in the dialog; `none` means "both".
  final BoardSyncDirection direction;
}

/// Shows the sync plan preview and returns the user's selection, or `null`
/// when the dialog was dismissed.
///
/// The plan is fully built before this dialog opens, so the preview is a pure
/// render of [BoardSyncPlan]: no device access happens while it is open.
Future<BoardSyncPreviewResult?> showBoardSyncPreviewDialog(
  BuildContext context, {
  required BoardSyncPlan plan,
  required String localRoot,
}) {
  return showDialog<BoardSyncPreviewResult>(
    context: context,
    builder: (context) =>
        _BoardSyncPreviewDialog(plan: plan, localRoot: localRoot),
  );
}

class _BoardSyncPreviewDialog extends StatefulWidget {
  const _BoardSyncPreviewDialog({required this.plan, required this.localRoot});

  final BoardSyncPlan plan;
  final String localRoot;

  @override
  State<_BoardSyncPreviewDialog> createState() =>
      _BoardSyncPreviewDialogState();
}

class _BoardSyncPreviewDialogState extends State<_BoardSyncPreviewDialog> {
  late Set<String> _selected;
  late BoardSyncDirection _direction;

  @override
  void initState() {
    super.initState();
    // Default selection: every actionable row. Conflicts start unchecked
    // because silently overwriting either side would lose user edits.
    _selected = {
      for (final entry in widget.plan.actionable) entry.relativePath,
    };
    _direction = BoardSyncDirection.none;
  }

  List<BoardSyncEntry> get _visibleEntries {
    if (_direction == BoardSyncDirection.localToBoard) {
      return widget.plan.entries
          .where(
            (entry) =>
                entry.action == BoardSyncAction.uploadNew ||
                entry.action == BoardSyncAction.uploadChanged ||
                entry.action == BoardSyncAction.unchanged,
          )
          .toList(growable: false);
    }
    if (_direction == BoardSyncDirection.boardToLocal) {
      return widget.plan.entries
          .where(
            (entry) =>
                entry.action == BoardSyncAction.downloadNew ||
                entry.action == BoardSyncAction.downloadChanged ||
                entry.action == BoardSyncAction.unchanged,
          )
          .toList(growable: false);
    }
    return widget.plan.entries;
  }

  int get _selectedBytes => widget.plan.actionable
      .where((entry) => _selected.contains(entry.relativePath))
      .fold(0, (sum, entry) => sum + entry.transferBytes);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _visibleEntries;
    final actionable = _selected.length;
    return AlertDialog(
      icon: const Icon(Icons.sync_alt),
      title: const Text('同步本地工作区到设备'),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地：${widget.localRoot}\n设备：${widget.plan.boardRoot}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _buildDirectionSelector(scheme),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '共 ${widget.plan.entries.length} 个文件：'
                    '上传 ${widget.plan.uploadCount} · '
                    '下载 ${widget.plan.downloadCount} · '
                    '相同 ${widget.plan.unchangedCount} · '
                    '冲突 ${widget.plan.conflicts.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () {
                          final selectable = entries
                              .where((entry) => entry.isChanged)
                              .map((entry) => entry.relativePath)
                              .toSet();
                          setState(() {
                            if (_selected.containsAll(selectable)) {
                              _selected = {};
                            } else {
                              _selected = {..._selected, ...selectable};
                            }
                          });
                        },
                  child: const Text('全选/全不选'),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('没有可同步的文件'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) =>
                          _buildEntryRow(context, entries[index], scheme),
                    ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Text(
              '已选择 $actionable 个文件，'
              '约 ${formatTransferBytes(_selectedBytes)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: actionable == 0
              ? null
              : () => Navigator.pop(
                  context,
                  BoardSyncPreviewResult(
                    // Only rows currently visible *and* checked are returned:
                    // switching the direction chip must not keep transferring
                    // rows the user can no longer see.
                    selectedPaths: {
                      for (final entry in _visibleEntries)
                        if (entry.isChanged &&
                            _selected.contains(entry.relativePath))
                          entry.relativePath,
                    },
                    direction: _direction,
                  ),
                ),
          icon: const Icon(Icons.play_arrow),
          label: Text('同步 $actionable 个'),
        ),
      ],
    );
  }

  Widget _buildDirectionSelector(ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('双向（默认）'),
          selected: _direction == BoardSyncDirection.none,
          onSelected: (_) =>
              setState(() => _direction = BoardSyncDirection.none),
        ),
        ChoiceChip(
          label: const Text('仅本地 → 设备'),
          selected: _direction == BoardSyncDirection.localToBoard,
          onSelected: (_) =>
              setState(() => _direction = BoardSyncDirection.localToBoard),
        ),
        ChoiceChip(
          label: const Text('仅设备 → 本地'),
          selected: _direction == BoardSyncDirection.boardToLocal,
          onSelected: (_) =>
              setState(() => _direction = BoardSyncDirection.boardToLocal),
        ),
      ],
    );
  }

  Widget _buildEntryRow(
    BuildContext context,
    BoardSyncEntry entry,
    ColorScheme scheme,
  ) {
    final checked = _selected.contains(entry.relativePath);
    final selectable = entry.isChanged;
    final (icon, color, label) = _describeAction(entry.action, scheme);
    final sizeLabel = entry.transferBytes > 0
        ? formatTransferBytes(entry.transferBytes)
        : '';
    return CheckboxListTile(
      dense: true,
      value: selectable && checked,
      onChanged: selectable
          ? (value) {
              setState(() {
                if (value ?? false) {
                  _selected.add(entry.relativePath);
                } else {
                  _selected.remove(entry.relativePath);
                }
              });
            }
          : null,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: Icon(icon, size: 18, color: color),
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.relativePath,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          if (sizeLabel.isNotEmpty)
            Text(
              sizeLabel,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
      subtitle: Text(
        entry.note == null ? label : '$label · ${entry.note}',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }

  (IconData, Color, String) _describeAction(
    BoardSyncAction action,
    ColorScheme scheme,
  ) {
    switch (action) {
      case BoardSyncAction.uploadNew:
        return (Icons.upload_outlined, scheme.primary, '新增（上传）');
      case BoardSyncAction.uploadChanged:
        return (Icons.arrow_upward, scheme.primary, '修改（上传）');
      case BoardSyncAction.downloadNew:
        return (Icons.download_outlined, scheme.tertiary, '仅设备端存在（下载）');
      case BoardSyncAction.downloadChanged:
        return (Icons.arrow_downward, scheme.tertiary, '修改（下载）');
      case BoardSyncAction.unchanged:
        return (Icons.check, scheme.onSurfaceVariant, '相同');
      case BoardSyncAction.conflict:
        return (Icons.warning_amber_rounded, scheme.error, '冲突（需选择）');
    }
  }
}

/// Transfer progress row with a cancel button.
///
/// Kept in the file page's module because the cancel affordance belongs to the
/// batch that the page started; the token itself lives in
/// [FileTransferProgressNotifier] so other call sites share the same cancel.
class FileTransferProgressBar extends ConsumerWidget {
  const FileTransferProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileTransferProgressProvider);
    final scheme = Theme.of(context).colorScheme;
    if (!state.isActive) return const SizedBox.shrink();

    final color = state.failed
        ? scheme.error
        : state.cancelled || state.cancelRequested
        ? scheme.tertiary
        : scheme.primary;
    final label = state.message ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: state.failed
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            state.direction == FileTransferDirection.download
                ? Icons.file_download_outlined
                : Icons.file_upload_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: state.failed ? scheme.error : null,
                        ),
                      ),
                    ),
                    if (state.currentFile != null)
                      Flexible(
                        child: Text(
                          state.currentFile!.split(RegExp(r'[\\/]')).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: state.progress,
                  minHeight: 3,
                  color: color,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Cancel is only offered while a batch is running. Pressing it sets a
          // flag; the running loop stops at the next whole-file boundary so the
          // device and its REPL stay usable.
          if (state.canCancel)
            TextButton.icon(
              onPressed: () => ref
                  .read(fileTransferProgressProvider.notifier)
                  .requestCancel(),
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text('取消'),
            )
          else if (state.cancelRequested)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '取消中…',
                style: TextStyle(fontSize: 12, color: scheme.tertiary),
              ),
            ),
        ],
      ),
    );
  }
}

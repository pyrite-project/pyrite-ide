import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';

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

  /// The `.pyrsyncignore` group starts folded: the rows the user asked us to
  /// leave alone must not push the rows that need a decision off screen.
  bool _ignoredExpanded = false;

  @override
  void initState() {
    super.initState();
    // Default selection: every actionable row the ignore file does not cover.
    // Conflicts start unchecked because silently overwriting either side would
    // lose user edits.
    _selected = {
      for (final entry in widget.plan.defaultSelection) entry.relativePath,
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

  /// Rows listed one by one, in path order.
  List<BoardSyncEntry> get _regularEntries => _visibleEntries
      .where((entry) => !entry.ignoredByDefault)
      .toList(growable: false);

  /// Rows folded into the single `.pyrsyncignore` group.
  List<BoardSyncEntry> get _ignoredEntries => _visibleEntries
      .where((entry) => entry.ignoredByDefault)
      .toList(growable: false);

  int get _selectedBytes => widget.plan.actionable
      .where((entry) => _selected.contains(entry.relativePath))
      .fold(0, (sum, entry) => sum + entry.transferBytes);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _visibleEntries;
    final regular = _regularEntries;
    final ignored = _ignoredEntries;
    final actionable = _selected.length;
    return AlertDialog(
      icon: const Icon(Icons.sync_alt),
      title: Text(translateInContext(context, I18nKey.devicesSyncTitle)),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translateInContextWithReplacements(
                context,
                I18nKey.devicesSyncRoots,
                {'local': widget.localRoot, 'board': widget.plan.boardRoot},
              ),
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
                    translateInContextWithReplacements(
                      context,
                      I18nKey.devicesSyncSummary,
                      {
                        'count': '${widget.plan.entries.length}',
                        'upload': '${widget.plan.uploadCount}',
                        'download': '${widget.plan.downloadCount}',
                        'unchanged': '${widget.plan.unchangedCount}',
                        'conflict': '${widget.plan.conflicts.length}',
                      },
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () {
                          // Deliberately scoped to the rows listed one by one:
                          // selecting paths that `.pyrsyncignore` asked us to
                          // skip must stay a per-row or per-group decision, not
                          // a side effect of "select all".
                          final selectable = regular
                              .where((entry) => entry.isChanged)
                              .map((entry) => entry.relativePath)
                              .toSet();
                          setState(() {
                            if (selectable.isNotEmpty &&
                                _selected.containsAll(selectable)) {
                              _selected.removeAll(selectable);
                            } else {
                              _selected.addAll(selectable);
                            }
                          });
                        },
                  child: Text(
                    translateInContext(context, I18nKey.devicesSyncToggleAll),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        translateInContext(context, I18nKey.devicesSyncEmpty),
                      ),
                    )
                  : ListView.builder(
                      // Folded ignored rows cost exactly one header line.
                      itemCount:
                          regular.length +
                          (ignored.isEmpty ? 0 : 1) +
                          (_ignoredExpanded ? ignored.length : 0),
                      itemBuilder: (context, index) {
                        if (index < regular.length) {
                          return _buildEntryRow(
                            context,
                            regular[index],
                            scheme,
                          );
                        }
                        final groupIndex = index - regular.length;
                        if (groupIndex == 0) {
                          return _buildIgnoredGroup(context, ignored, scheme);
                        }
                        return _buildEntryRow(
                          context,
                          ignored[groupIndex - 1],
                          scheme,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Text(
              translateInContextWithReplacements(
                context,
                I18nKey.devicesSyncSelected,
                {
                  'count': '$actionable',
                  'size': formatTransferBytes(_selectedBytes),
                },
              ),
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
          child: Text(translateInContext(context, I18nKey.devicesSyncCancel)),
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
          label: Text(
            translateInContextWithReplacements(
              context,
              I18nKey.devicesSyncApply,
              {'count': '$actionable'},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDirectionSelector(ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: Text(
            translateInContext(context, I18nKey.devicesSyncDirectionBoth),
          ),
          selected: _direction == BoardSyncDirection.none,
          onSelected: (_) =>
              setState(() => _direction = BoardSyncDirection.none),
        ),
        ChoiceChip(
          label: Text(
            translateInContext(context, I18nKey.devicesSyncDirectionLocal),
          ),
          selected: _direction == BoardSyncDirection.localToBoard,
          onSelected: (_) =>
              setState(() => _direction = BoardSyncDirection.localToBoard),
        ),
        ChoiceChip(
          label: Text(
            translateInContext(context, I18nKey.devicesSyncDirectionBoard),
          ),
          selected: _direction == BoardSyncDirection.boardToLocal,
          onSelected: (_) =>
              setState(() => _direction = BoardSyncDirection.boardToLocal),
        ),
      ],
    );
  }

  /// Header that folds every `.pyrsyncignore` row into one collapsed group.
  ///
  /// Tapping the row toggles the fold; the tri-state checkbox is a separate
  /// control so the whole group can be opted back in without expanding it.
  Widget _buildIgnoredGroup(
    BuildContext context,
    List<BoardSyncEntry> ignored,
    ColorScheme scheme,
  ) {
    final selectable = ignored
        .where((entry) => entry.isChanged)
        .toList(growable: false);
    final selectedCount = selectable
        .where((entry) => _selected.contains(entry.relativePath))
        .length;
    // Tri-state: nothing ticked, everything ticked, or a mix. An empty group
    // reads as "nothing ticked" because there is nothing to opt in to.
    final bool? groupValue = switch (selectedCount) {
      0 => false,
      _ when selectedCount == selectable.length => true,
      _ => null,
    };
    return ListTile(
      dense: true,
      onTap: () => setState(() => _ignoredExpanded = !_ignoredExpanded),
      leading: Checkbox(
        tristate: true,
        value: groupValue,
        onChanged: selectable.isEmpty
            ? null
            : (_) {
                setState(() {
                  if (selectedCount == selectable.length) {
                    _selected.removeAll(
                      selectable.map((entry) => entry.relativePath),
                    );
                  } else {
                    _selected.addAll(
                      selectable.map((entry) => entry.relativePath),
                    );
                  }
                });
              },
      ),
      title: Text(
        translateInContextWithReplacements(
          context,
          I18nKey.devicesSyncIgnoredGroup,
          {'count': '${ignored.length}'},
        ),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        translateInContext(context, I18nKey.devicesSyncIgnoredHint),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
      trailing: Icon(
        _ignoredExpanded ? Icons.expand_less : Icons.expand_more,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
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
        return (
          Icons.upload_outlined,
          scheme.primary,
          translateInContext(context, I18nKey.devicesSyncRowAdded),
        );
      case BoardSyncAction.uploadChanged:
        return (
          Icons.arrow_upward,
          scheme.primary,
          translateInContext(context, I18nKey.devicesSyncRowModifiedUpload),
        );
      case BoardSyncAction.downloadNew:
        return (
          Icons.download_outlined,
          scheme.tertiary,
          translateInContext(context, I18nKey.devicesSyncRowBoardOnly),
        );
      case BoardSyncAction.downloadChanged:
        return (
          Icons.arrow_downward,
          scheme.tertiary,
          translateInContext(context, I18nKey.devicesSyncRowModifiedDownload),
        );
      case BoardSyncAction.unchanged:
        return (
          Icons.check,
          scheme.onSurfaceVariant,
          translateInContext(context, I18nKey.devicesSyncRowUnchanged),
        );
      case BoardSyncAction.conflict:
        return (
          Icons.warning_amber_rounded,
          scheme.error,
          translateInContext(context, I18nKey.devicesSyncRowConflict),
        );
    }
  }
}

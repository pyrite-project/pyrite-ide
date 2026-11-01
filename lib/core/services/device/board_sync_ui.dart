import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
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
    this.overrides = const {},
  });

  /// Relative paths the user left checked.
  final Set<String> selectedPaths;

  /// Direction chosen in the dialog; `none` means "both".
  final BoardSyncDirection direction;

  /// Conflict rows the user resolved here: [BoardSyncAction.uploadChanged]
  /// keeps the local copy, [BoardSyncAction.downloadChanged] keeps the device
  /// copy. Empty when nothing needed a decision.
  final Map<String, BoardSyncAction> overrides;
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

  /// Conflict rows the user already resolved, keyed by relative path.
  final Map<String, BoardSyncAction> _resolved = {};

  /// The `.pyrsyncignore` rows start folded: files the user asked us to leave
  /// alone must not push the rows that need a decision off screen.
  bool _ignoredExpanded = false;

  static const _segmentLabelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  @override
  void initState() {
    super.initState();
    // Default selection: every actionable row the ignore file does not cover.
    // Conflicts start unresolved because silently overwriting either side would
    // lose user edits.
    _selected = {
      for (final entry in widget.plan.defaultSelection) entry.relativePath,
    };
    _direction = BoardSyncDirection.none;
  }

  /// Rows worth showing: files that will move, plus conflicts.
  ///
  /// Identical files are left out. The dialog answers "what will happen"; a row
  /// that cannot be acted on is noise, and the arrow column already says which
  /// way every remaining file goes.
  List<BoardSyncEntry> get _visibleEntries {
    final changed = widget.plan.entries.where((entry) => entry.isChanged);
    return switch (_direction) {
      BoardSyncDirection.localToBoard =>
        changed
            .where(
              (entry) =>
                  entry.action == BoardSyncAction.uploadNew ||
                  entry.action == BoardSyncAction.uploadChanged,
            )
            .toList(growable: false),
      BoardSyncDirection.boardToLocal =>
        changed
            .where(
              (entry) =>
                  entry.action == BoardSyncAction.downloadNew ||
                  entry.action == BoardSyncAction.downloadChanged,
            )
            .toList(growable: false),
      BoardSyncDirection.none => changed.toList(growable: false),
    };
  }

  /// Rows listed one by one, in path order.
  List<BoardSyncEntry> get _regularEntries => _visibleEntries
      .where((entry) => !entry.ignoredByDefault)
      .toList(growable: false);

  /// Rows folded into the single `.pyrsyncignore` group.
  List<BoardSyncEntry> get _ignoredEntries => _visibleEntries
      .where((entry) => entry.ignoredByDefault)
      .toList(growable: false);

  /// Changed rows the ignore file does not cover, in both directions.
  ///
  /// The switch counts these, not the whole plan: ignored rows are folded and
  /// unticked, so counting them would promise more than the list shows.
  Iterable<BoardSyncEntry> get _regularChanged => widget.plan.entries.where(
    (entry) => entry.isChanged && !entry.ignoredByDefault,
  );

  int get _uploadTotal => _regularChanged
      .where(
        (entry) =>
            entry.action == BoardSyncAction.uploadNew ||
            entry.action == BoardSyncAction.uploadChanged,
      )
      .length;

  int get _downloadTotal => _regularChanged
      .where(
        (entry) =>
            entry.action == BoardSyncAction.downloadNew ||
            entry.action == BoardSyncAction.downloadChanged,
      )
      .length;

  /// Action that will actually run for [entry]; a resolved conflict carries the
  /// side the user picked.
  BoardSyncAction _effectiveAction(BoardSyncEntry entry) =>
      _resolved[entry.relativePath] ?? entry.action;

  /// Conflicts have no direction until the user picks a side, so they cannot be
  /// checked yet: the two side buttons replace the checkbox.
  bool _needsDecision(BoardSyncEntry entry) =>
      entry.action == BoardSyncAction.conflict &&
      _resolved[entry.relativePath] == null;

  int _bytesFor(BoardSyncEntry entry) {
    switch (_effectiveAction(entry)) {
      case BoardSyncAction.uploadNew:
      case BoardSyncAction.uploadChanged:
        return entry.local?.size ?? 0;
      case BoardSyncAction.downloadNew:
      case BoardSyncAction.downloadChanged:
        return entry.board?.size ?? 0;
      case BoardSyncAction.unchanged:
      case BoardSyncAction.conflict:
        return 0;
    }
  }

  /// Only visible rows count: switching the direction chip must not keep
  /// counting rows the user can no longer see, since those are also the only
  /// paths handed back to the executor.
  int get _selectedCount => _visibleEntries
      .where((entry) => _selected.contains(entry.relativePath))
      .length;

  int get _selectedBytes => _visibleEntries
      .where((entry) => _selected.contains(entry.relativePath))
      .fold(0, (sum, entry) => sum + _bytesFor(entry));

  void _setSelected(BoardSyncEntry entry, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(entry.relativePath);
      } else {
        _selected.remove(entry.relativePath);
      }
    });
  }

  /// Picking a side both records the direction and includes the row; tapping
  /// the chosen side again drops it back to "needs a decision".
  void _resolve(BoardSyncEntry entry, BoardSyncAction action) {
    setState(() {
      if (_resolved[entry.relativePath] == action) {
        _resolved.remove(entry.relativePath);
        _selected.remove(entry.relativePath);
      } else {
        _resolved[entry.relativePath] = action;
        _selected.add(entry.relativePath);
      }
    });
  }

  void _toggleAll(List<BoardSyncEntry> selectable, bool? current) {
    setState(() {
      final paths = selectable.map((entry) => entry.relativePath);
      if (current == true) {
        _selected.removeAll(paths);
      } else {
        _selected.addAll(paths);
      }
    });
  }

  BoardSyncPreviewResult _buildResult() {
    final selected = {
      for (final entry in _visibleEntries)
        if (entry.isChanged && _selected.contains(entry.relativePath))
          entry.relativePath,
    };
    return BoardSyncPreviewResult(
      selectedPaths: selected,
      direction: _direction,
      overrides: {
        for (final entry in _resolved.entries)
          if (selected.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final regular = _regularEntries;
    final ignored = _ignoredEntries;
    final selectedCount = _selectedCount;
    // One list so the folded ignore group sits at the end of the rows instead
    // of becoming a second scroll area.
    final itemCount =
        regular.length +
        (ignored.isEmpty ? 0 : 1 + (_ignoredExpanded ? ignored.length : 0));
    // The dialog also runs on phones: every size is derived from the viewport
    // minus what AlertDialog and the content padding already reserve, so a
    // 320dp window shrinks instead of overflowing. No artificial floor: a
    // minimum wider than the screen is exactly how the old version broke when
    // the desktop window was resized to a phone width.
    final media = MediaQuery.sizeOf(context);
    final compact = media.width < 520;
    final horizontalInset = compact ? 16.0 : 24.0;
    final contentWidth = (media.width - 80 - horizontalInset * 2).clamp(
      0.0,
      620.0,
    );
    // 62% keeps the dialog off the window edges on short desktop windows; the
    // subtraction reserves the icon, title, actions and the dialog's own insets
    // so the list never squeezes them out.
    final contentHeight = math
        .min(media.height * 0.62, media.height - 284)
        .clamp(160.0, 460.0);
    return AlertDialog(
      icon: const Icon(Icons.sync_alt),
      title: Text(translateInContext(context, I18nKey.devicesSyncTitle)),
      contentPadding: EdgeInsets.fromLTRB(
        horizontalInset,
        8,
        horizontalInset,
        12,
      ),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRootsRow(scheme),
            const SizedBox(height: 12),
            _buildControlRow(context),
            const SizedBox(height: 4),
            const Divider(height: 1),
            Expanded(
              child: itemCount == 0
                  ? Center(
                      child: Text(
                        translateInContext(context, I18nKey.devicesSyncEmpty),
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (index < regular.length) {
                          return _buildEntryRow(
                            context,
                            regular[index],
                            scheme,
                          );
                        }
                        if (index == regular.length) {
                          return _buildIgnoredHeader(context, scheme, ignored);
                        }
                        return _buildEntryRow(
                          context,
                          ignored[index - regular.length - 1],
                          scheme,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              translateInContextWithReplacements(
                context,
                I18nKey.devicesSyncSelected,
                {
                  'count': '$selectedCount',
                  'size': formatTransferBytes(_selectedBytes),
                },
              ),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
          onPressed: selectedCount == 0
              ? null
              : () => Navigator.pop(context, _buildResult()),
          icon: const Icon(Icons.play_arrow),
          label: Text(translateInContext(context, I18nKey.devicesSyncApply)),
        ),
      ],
    );
  }

  /// Source and destination, as two chips. The full path lives in the tooltip
  /// so the row stays one line.
  Widget _buildRootsRow(ColorScheme scheme) {
    return Row(
      children: [
        Flexible(
          child: _SyncRootChip(
            icon: Icons.folder_outlined,
            label: _shortRoot(widget.localRoot),
            tooltip: widget.localRoot,
            scheme: scheme,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            Icons.arrow_right_alt,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Flexible(
          child: _SyncRootChip(
            icon: Icons.memory,
            label: widget.plan.boardRoot,
            tooltip: widget.plan.boardRoot,
            scheme: scheme,
          ),
        ),
      ],
    );
  }

  /// Keeps the last two segments of a path: enough to recognise the project,
  /// short enough to never wrap.
  String _shortRoot(String path) {
    final parts = path
        .split(RegExp(r'[\\/]'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length <= 2) return path;
    return '…/${parts.skip(parts.length - 2).join('/')}';
  }

  /// Master checkbox plus the direction switch.
  ///
  /// Two layouts. On a wide dialog the switch sits beside the master checkbox
  /// and each segment carries its count. Once the row can no longer hold three
  /// labelled segments (phone widths) the checkbox moves to its own line and
  /// the switch spans the full width; counts are the first thing to go, icons
  /// the second, so the control never overflows from 280dp up.
  Widget _buildControlRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uploads = _uploadTotal;
    final downloads = _downloadTotal;
    // Ignored rows stay out of "select all": they are opt-in by definition.
    final selectable = _regularEntries
        .where((entry) => !_needsDecision(entry))
        .toList(growable: false);
    final checked = selectable
        .where((entry) => _selected.contains(entry.relativePath))
        .length;
    final bool? masterValue = selectable.isEmpty
        ? false
        : checked == selectable.length
        ? true
        : checked == 0
        ? false
        : null;

    final master = Tooltip(
      message: translateInContext(context, I18nKey.devicesSyncToggleAll),
      child: Checkbox(
        value: masterValue,
        tristate: true,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: selectable.isEmpty
            ? null
            : (_) => _toggleAll(selectable, masterValue),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 460;
        final showCounts = constraints.maxWidth >= 420;
        final showIcons = constraints.maxWidth >= 260;

        Widget segmentLabel(I18nKey key, int count) => Text(
          showCounts
              ? '${translateInContext(context, key)} $count'
              : translateInContext(context, key),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _segmentLabelStyle,
        );

        Widget segmentIcon(IconData icon) => Icon(icon, size: 16);

        final segments = SegmentedButton<BoardSyncDirection>(
          showSelectedIcon: false,
          expandedInsets: stacked ? EdgeInsets.zero : null,
          style: _segmentStyle(scheme, compact: stacked),
          segments: [
            ButtonSegment(
              value: BoardSyncDirection.none,
              icon: showIcons ? segmentIcon(Icons.swap_horiz) : null,
              label: segmentLabel(
                I18nKey.devicesSyncDirBoth,
                uploads + downloads,
              ),
              tooltip: translateInContext(
                context,
                I18nKey.devicesSyncDirectionBoth,
              ),
            ),
            ButtonSegment(
              value: BoardSyncDirection.localToBoard,
              enabled: uploads > 0,
              icon: showIcons ? segmentIcon(Icons.arrow_upward_rounded) : null,
              label: segmentLabel(I18nKey.devicesSyncDirUpload, uploads),
              tooltip: translateInContext(
                context,
                I18nKey.devicesSyncDirectionLocal,
              ),
            ),
            ButtonSegment(
              value: BoardSyncDirection.boardToLocal,
              enabled: downloads > 0,
              icon: showIcons
                  ? segmentIcon(Icons.arrow_downward_rounded)
                  : null,
              label: segmentLabel(I18nKey.devicesSyncDirDownload, downloads),
              tooltip: translateInContext(
                context,
                I18nKey.devicesSyncDirectionBoard,
              ),
            ),
          ],
          selected: {_direction},
          onSelectionChanged: (selection) =>
              setState(() => _direction = selection.first),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(width: 40, height: 36, child: Center(child: master)),
                  Text(
                    translateInContext(context, I18nKey.devicesSyncSelectAll),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              segments,
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: 40, height: 40, child: Center(child: master)),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: segments,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Filled segment styling: `surfaceContainerHighest` track, `primary`
  /// selection. Colours are resolved explicitly because some plugin themes
  /// leave `outline` almost equal to the dialog surface, which made the
  /// outlined default read as three plain labels.
  ButtonStyle _segmentStyle(ColorScheme scheme, {required bool compact}) {
    return ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
      ),
      side: const WidgetStatePropertyAll(BorderSide.none),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant,
      ),
    );
  }

  /// One folded line for the `.pyrsyncignore` matches. Expanding it reveals the
  /// same rows as everywhere else, so nothing has to explain the rule.
  Widget _buildIgnoredHeader(
    BuildContext context,
    ColorScheme scheme,
    List<BoardSyncEntry> ignored,
  ) {
    final selectable = ignored
        .where((entry) => !_needsDecision(entry))
        .toList(growable: false);
    final checked = selectable
        .where((entry) => _selected.contains(entry.relativePath))
        .length;
    final bool? groupValue = selectable.isEmpty
        ? false
        : checked == selectable.length
        ? true
        : checked == 0
        ? false
        : null;

    return InkWell(
      onTap: () => setState(() => _ignoredExpanded = !_ignoredExpanded),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Center(
                child: Checkbox(
                  value: groupValue,
                  tristate: true,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: selectable.isEmpty
                      ? null
                      : (_) => _toggleAll(selectable, groupValue),
                ),
              ),
            ),
            Expanded(
              child: Text(
                translateInContextWithReplacements(
                  context,
                  I18nKey.devicesSyncIgnoredGroup,
                  {'count': '${ignored.length}'},
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Icon(
              _ignoredExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryRow(
    BuildContext context,
    BoardSyncEntry entry,
    ColorScheme scheme,
  ) {
    final isConflict = entry.action == BoardSyncAction.conflict;
    final needsDecision = _needsDecision(entry);
    final resolvedAction = _resolved[entry.relativePath];
    final checked = _selected.contains(entry.relativePath);
    final (icon, color, labelKey) = _describeAction(
      resolvedAction ?? entry.action,
      scheme,
    );
    final bytes = _bytesFor(entry);
    final label = translateInContext(context, labelKey);
    final detail = entry.note == null || resolvedAction != null
        ? label
        : '$label · ${entry.note}';

    return Tooltip(
      message: detail,
      waitDuration: const Duration(milliseconds: 700),
      child: InkWell(
        onTap: isConflict ? null : () => _setSelected(entry, !checked),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Center(
                  child: isConflict
                      ? Icon(
                          resolvedAction == null
                              ? Icons.priority_high_rounded
                              : Icons.check_rounded,
                          size: 16,
                          color: resolvedAction == null ? scheme.error : color,
                        )
                      : Checkbox(
                          value: checked,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (value) =>
                              _setSelected(entry, value ?? false),
                        ),
                ),
              ),
              Expanded(
                child: Text(
                  entry.relativePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: needsDecision
                        ? scheme.error
                        : entry.ignoredByDefault
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (bytes > 0) ...[
                const SizedBox(width: 12),
                Text(
                  formatTransferBytes(bytes),
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              if (isConflict)
                _ConflictSidePicker(
                  resolved: resolvedAction,
                  onPick: (action) => _resolve(entry, action),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Direction icon, colour and tooltip label for one action.
  ///
  /// The icon column is the only per-row explanation: an up arrow means the
  /// file goes to the device, a down arrow means it comes back.
  (IconData, Color, I18nKey) _describeAction(
    BoardSyncAction action,
    ColorScheme scheme,
  ) {
    switch (action) {
      case BoardSyncAction.uploadNew:
        return (
          Icons.arrow_upward_rounded,
          scheme.primary,
          I18nKey.devicesSyncRowAdded,
        );
      case BoardSyncAction.uploadChanged:
        return (
          Icons.arrow_upward_rounded,
          scheme.primary,
          I18nKey.devicesSyncRowModifiedUpload,
        );
      case BoardSyncAction.downloadNew:
        return (
          Icons.arrow_downward_rounded,
          scheme.tertiary,
          I18nKey.devicesSyncRowBoardOnly,
        );
      case BoardSyncAction.downloadChanged:
        return (
          Icons.arrow_downward_rounded,
          scheme.tertiary,
          I18nKey.devicesSyncRowModifiedDownload,
        );
      case BoardSyncAction.unchanged:
        return (
          Icons.check,
          scheme.onSurfaceVariant,
          I18nKey.devicesSyncRowUnchanged,
        );
      case BoardSyncAction.conflict:
        return (
          Icons.priority_high_rounded,
          scheme.error,
          I18nKey.devicesSyncRowConflict,
        );
    }
  }
}

/// Local or device root, rendered as one compact chip.
class _SyncRootChip extends StatelessWidget {
  const _SyncRootChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two side buttons for a conflicting file: keep the local copy or the device
/// copy. Replaces the checkbox, because a conflict has no default direction.
class _ConflictSidePicker extends StatelessWidget {
  const _ConflictSidePicker({required this.resolved, required this.onPick});

  final BoardSyncAction? resolved;
  final ValueChanged<BoardSyncAction> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPill(
          context,
          scheme,
          I18nKey.devicesSyncKeepLocal,
          BoardSyncAction.uploadChanged,
        ),
        const SizedBox(width: 4),
        _buildPill(
          context,
          scheme,
          I18nKey.devicesSyncKeepBoard,
          BoardSyncAction.downloadChanged,
        ),
      ],
    );
  }

  Widget _buildPill(
    BuildContext context,
    ColorScheme scheme,
    I18nKey key,
    BoardSyncAction action,
  ) {
    final selected = resolved == action;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onPick(action),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          border: Border.all(
            color: selected ? Colors.transparent : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          translateInContext(context, key),
          style: TextStyle(
            fontSize: 11,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
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
              label: Text(
                translateInContext(context, I18nKey.devicesSyncCancel),
              ),
            )
          else if (state.cancelRequested)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                I18nKey.devicesSyncCancelling.fallback,
                style: TextStyle(fontSize: 12, color: scheme.tertiary),
              ),
            ),
        ],
      ),
    );
  }
}

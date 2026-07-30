import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:super_tree/super_tree.dart';

// ---------------------------------------------------------------------------
// Diff info
// ---------------------------------------------------------------------------

class DiffInfo {
  final List<(int startLine, int endLine)> addedRanges;
  final List<({int afterLine, String content})> removedRanges;
  final List<String> unifiedLines;
  final int addCount;
  final int removeCount;

  DiffInfo({
    required this.addedRanges,
    required this.removedRanges,
    required this.unifiedLines,
    required this.addCount,
    required this.removeCount,
  });
}

DiffInfo computeDiff(String oldText, String newText) {
  final a = oldText.split('\n');
  final b = newText.split('\n');
  final ops = _normalizeEditOrder(_myersDiff(a, b));

  final addedRanges = <(int, int)>[];
  final removedRanges = <({int afterLine, String content})>[];
  final unifiedLines = <String>[];
  int addCount = 0, removeCount = 0;
  int newPos = 0;

  int? addStart;
  int? remAfterLine;
  final remBuf = StringBuffer();

  void flushAdd() {
    if (addStart != null) {
      addedRanges.add((addStart!, newPos - 1));
      addStart = null;
    }
  }

  void flushRem() {
    if (remBuf.isNotEmpty) {
      removedRanges.add((afterLine: remAfterLine!, content: remBuf.toString()));
      remBuf.clear();
      remAfterLine = null;
    }
  }

  for (final op in ops) {
    if (op.type == '=') {
      flushAdd();
      flushRem();
      unifiedLines.add(' ${op.text}');
      newPos++;
    } else if (op.type == '+') {
      addCount++;
      unifiedLines.add('+${op.text}');
      addStart ??= newPos;
      newPos++;
      flushRem();
    } else {
      removeCount++;
      unifiedLines.add('-${op.text}');
      remAfterLine ??= newPos - 1;
      if (remBuf.isNotEmpty) remBuf.write('\n');
      remBuf.write(op.text);
      flushAdd();
    }
  }
  flushAdd();
  flushRem();

  return DiffInfo(
    addedRanges: addedRanges,
    removedRanges: removedRanges,
    unifiedLines: unifiedLines,
    addCount: addCount,
    removeCount: removeCount,
  );
}

class _DiffOp {
  final String type;
  final String text;
  final int oldLine;
  final int newLine;
  _DiffOp(this.type, this.text, {required this.oldLine, required this.newLine});
}

List<_DiffOp> _myersDiff(List<String> oldLines, List<String> newLines) {
  final oldLength = oldLines.length;
  final newLength = newLines.length;
  final maxDistance = oldLength + newLength;
  var furthestByDiagonal = <int, int>{1: 0};
  final trace = <Map<int, int>>[];

  for (var distance = 0; distance <= maxDistance; distance += 1) {
    final nextFurthestByDiagonal = <int, int>{};
    for (var diagonal = -distance; diagonal <= distance; diagonal += 2) {
      final canMoveDown =
          diagonal == -distance ||
          (diagonal != distance &&
              (furthestByDiagonal[diagonal - 1] ?? -1) <
                  (furthestByDiagonal[diagonal + 1] ?? -1));
      var oldIndex = canMoveDown
          ? furthestByDiagonal[diagonal + 1] ?? 0
          : (furthestByDiagonal[diagonal - 1] ?? 0) + 1;
      var newIndex = oldIndex - diagonal;

      while (oldIndex < oldLength &&
          newIndex < newLength &&
          oldLines[oldIndex] == newLines[newIndex]) {
        oldIndex += 1;
        newIndex += 1;
      }

      nextFurthestByDiagonal[diagonal] = oldIndex;
      if (oldIndex >= oldLength && newIndex >= newLength) {
        trace.add(nextFurthestByDiagonal);
        return _backtrackMyersDiff(trace, oldLines, newLines);
      }
    }
    trace.add(nextFurthestByDiagonal);
    furthestByDiagonal = nextFurthestByDiagonal;
  }

  return [
    for (var index = 0; index < oldLength; index += 1)
      _DiffOp('-', oldLines[index], oldLine: index, newLine: -1),
    for (var index = 0; index < newLength; index += 1)
      _DiffOp('+', newLines[index], oldLine: -1, newLine: index),
  ];
}

List<_DiffOp> _backtrackMyersDiff(
  List<Map<int, int>> trace,
  List<String> oldLines,
  List<String> newLines,
) {
  var oldIndex = oldLines.length;
  var newIndex = newLines.length;
  final ops = <_DiffOp>[];

  for (var distance = trace.length - 1; distance > 0; distance -= 1) {
    final previousFurthestByDiagonal = trace[distance - 1];
    final diagonal = oldIndex - newIndex;
    final movedDown =
        diagonal == -distance ||
        (diagonal != distance &&
            (previousFurthestByDiagonal[diagonal - 1] ?? -1) <
                (previousFurthestByDiagonal[diagonal + 1] ?? -1));
    final previousDiagonal = movedDown ? diagonal + 1 : diagonal - 1;
    final previousOldIndex = previousFurthestByDiagonal[previousDiagonal] ?? 0;
    final previousNewIndex = previousOldIndex - previousDiagonal;

    while (oldIndex > previousOldIndex && newIndex > previousNewIndex) {
      ops.add(
        _DiffOp(
          '=',
          oldLines[oldIndex - 1],
          oldLine: oldIndex - 1,
          newLine: newIndex - 1,
        ),
      );
      oldIndex -= 1;
      newIndex -= 1;
    }

    if (movedDown) {
      ops.add(
        _DiffOp(
          '+',
          newLines[newIndex - 1],
          oldLine: -1,
          newLine: newIndex - 1,
        ),
      );
      newIndex -= 1;
    } else {
      ops.add(
        _DiffOp(
          '-',
          oldLines[oldIndex - 1],
          oldLine: oldIndex - 1,
          newLine: -1,
        ),
      );
      oldIndex -= 1;
    }
  }

  while (oldIndex > 0 && newIndex > 0) {
    ops.add(
      _DiffOp(
        '=',
        oldLines[oldIndex - 1],
        oldLine: oldIndex - 1,
        newLine: newIndex - 1,
      ),
    );
    oldIndex -= 1;
    newIndex -= 1;
  }
  while (oldIndex > 0) {
    ops.add(
      _DiffOp('-', oldLines[oldIndex - 1], oldLine: oldIndex - 1, newLine: -1),
    );
    oldIndex -= 1;
  }
  while (newIndex > 0) {
    ops.add(
      _DiffOp('+', newLines[newIndex - 1], oldLine: -1, newLine: newIndex - 1),
    );
    newIndex -= 1;
  }

  return ops.reversed.toList();
}

List<_DiffOp> _normalizeEditOrder(List<_DiffOp> ops) {
  final normalized = <_DiffOp>[];
  final removed = <_DiffOp>[];
  final added = <_DiffOp>[];

  void flushEdits() {
    if (removed.isNotEmpty) {
      normalized.addAll(removed);
      removed.clear();
    }
    if (added.isNotEmpty) {
      normalized.addAll(added);
      added.clear();
    }
  }

  for (final op in ops) {
    if (op.type == '=') {
      flushEdits();
      normalized.add(op);
    } else if (op.type == '-') {
      removed.add(op);
    } else {
      added.add(op);
    }
  }
  flushEdits();

  return normalized;
}

// ---------------------------------------------------------------------------
// Pending upload/download diff state
// ---------------------------------------------------------------------------

class PendingUpload {
  final DiffInfo diff;
  final String localPath;
  final String targetPath;
  final String content;

  PendingUpload({
    required this.diff,
    required this.localPath,
    required this.targetPath,
    required this.content,
  });
}

class PendingDownload {
  final DiffInfo diff;
  final String boardPath;
  final String localPath;
  final String correspondingPath;
  final String content;

  PendingDownload({
    required this.diff,
    required this.boardPath,
    required this.localPath,
    required this.correspondingPath,
    required this.content,
  });
}

Map<String, StateProvider<PendingUpload?>> pendingUploadProviderMap = {};
Map<String, StateProvider<PendingDownload?>> pendingDownloadProviderMap = {};

// ---------------------------------------------------------------------------
// File transfer progress
// ---------------------------------------------------------------------------

enum FileTransferDirection { upload, download, move }

enum FileTransferScope { file, folder }

class FileTransferProgressState {
  const FileTransferProgressState({
    this.isActive = false,
    this.direction,
    this.scope,
    this.currentFile,
    this.currentIndex = 0,
    this.totalFiles = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.message,
    this.failed = false,
    this.bytesPerSecond,
  });

  final bool isActive;
  final FileTransferDirection? direction;
  final FileTransferScope? scope;
  final String? currentFile;
  final int currentIndex;
  final int totalFiles;
  final int bytesDone;
  final int bytesTotal;
  final String? message;
  final bool failed;
  final double? bytesPerSecond;

  double? get progress {
    if (bytesTotal <= 0) return null;
    return (bytesDone / bytesTotal).clamp(0, 1).toDouble();
  }

  FileTransferProgressState copyWith({
    bool? isActive,
    FileTransferDirection? direction,
    FileTransferScope? scope,
    String? currentFile,
    int? currentIndex,
    int? totalFiles,
    int? bytesDone,
    int? bytesTotal,
    String? message,
    bool? failed,
    double? bytesPerSecond,
  }) {
    return FileTransferProgressState(
      isActive: isActive ?? this.isActive,
      direction: direction ?? this.direction,
      scope: scope ?? this.scope,
      currentFile: currentFile ?? this.currentFile,
      currentIndex: currentIndex ?? this.currentIndex,
      totalFiles: totalFiles ?? this.totalFiles,
      bytesDone: bytesDone ?? this.bytesDone,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      message: message ?? this.message,
      failed: failed ?? this.failed,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    );
  }
}

class FileTransferProgressNotifier
    extends StateNotifier<FileTransferProgressState> {
  FileTransferProgressNotifier() : super(const FileTransferProgressState());

  Timer? _clearTimer;
  DateTime? _transferStartTime;
  DateTime? _lastProgressUpdate;

  void start({
    required FileTransferDirection direction,
    required FileTransferScope scope,
    required int totalFiles,
    String? message,
  }) {
    _clearTimer?.cancel();
    _transferStartTime = null;
    _lastProgressUpdate = null;
    state = FileTransferProgressState(
      isActive: true,
      direction: direction,
      scope: scope,
      totalFiles: totalFiles,
      message: message,
    );
  }

  void startFile({
    required String file,
    required int index,
    required int totalFiles,
    required int bytesTotal,
  }) {
    _transferStartTime = DateTime.now();
    _lastProgressUpdate = null;
    state = FileTransferProgressState(
      isActive: true,
      direction: state.direction,
      scope: state.scope,
      currentFile: file,
      currentIndex: index,
      totalFiles: totalFiles,
      bytesDone: 0,
      bytesTotal: bytesTotal,
      failed: false,
    );
  }

  void updateBytes(int done, int total) {
    final now = DateTime.now();
    final completed = total > 0 && done >= total;
    if (!completed &&
        _lastProgressUpdate != null &&
        now.difference(_lastProgressUpdate!) <
            const Duration(milliseconds: 50)) {
      return;
    }
    _lastProgressUpdate = now;
    double? speed;
    if (_transferStartTime != null && done > 0) {
      final elapsed =
          DateTime.now().difference(_transferStartTime!).inMilliseconds /
          1000.0;
      if (elapsed > 0) speed = done / elapsed;
    }
    state = state.copyWith(
      bytesDone: done,
      bytesTotal: total,
      bytesPerSecond: speed,
    );
  }

  void complete({required String message}) {
    state = state.copyWith(
      isActive: true,
      bytesDone: state.bytesTotal,
      message: message,
      failed: false,
    );
    _scheduleClear();
  }

  void fail(String message) {
    state = state.copyWith(isActive: true, message: message, failed: true);
    _scheduleClear(delay: const Duration(seconds: 5));
  }

  void clear() {
    _clearTimer?.cancel();
    state = const FileTransferProgressState();
  }

  void _scheduleClear({Duration delay = const Duration(seconds: 2)}) {
    _clearTimer?.cancel();
    _clearTimer = Timer(delay, clear);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }
}

final fileTransferProgressProvider =
    StateNotifierProvider<
      FileTransferProgressNotifier,
      FileTransferProgressState
    >((ref) => FileTransferProgressNotifier());

// ---------------------------------------------------------------------------
// Conflict resolution
// ---------------------------------------------------------------------------

enum FileConflictAction {
  overwrite,
  skip,
  overwriteAll,
  skipAll,
  showDiff,
  cancel,
}

Future<FileConflictAction> resolveConflict(
  BuildContext context, {
  required FileConflictAction? policy,
  required String sourcePath,
  required String targetPath,
  required bool isUpload,
  bool canShowDiff = false,
}) {
  if (policy == FileConflictAction.overwriteAll) {
    return Future.value(FileConflictAction.overwrite);
  }
  if (policy == FileConflictAction.skipAll) {
    return Future.value(FileConflictAction.skip);
  }
  return showFileConflictDialog(
    context,
    sourcePath: sourcePath,
    targetPath: targetPath,
    isUpload: isUpload,
    canShowDiff: canShowDiff,
  );
}

// ---------------------------------------------------------------------------
// Tree helpers
// ---------------------------------------------------------------------------

TreeNode<FileSystemItem>? getFocusFileNodeFromProvider(
  Ref ref,
  ProviderBase<TreeController<FileSystemItem>> controllerProvider,
) {
  final controller = ref.read(controllerProvider);
  final focusNodeId = controller.selectedNodeId ?? "/";
  final focusNode = controller.findNodeById(focusNodeId);
  if (focusNode?.data is FileItem) return focusNode;
  return null;
}

TreeNode<FileSystemItem>? getFocusFolderNodeFromProvider(
  Ref ref,
  ProviderBase<TreeController<FileSystemItem>> controllerProvider,
) {
  final controller = ref.read(controllerProvider);
  final focusNodeId = controller.selectedNodeId ?? "/";
  final focusNode = controller.findNodeById(focusNodeId);
  if (focusNode?.data is FolderItem) return focusNode;
  final lastSlash = focusNodeId.lastIndexOf('/');
  final parentPath = lastSlash > 0 ? focusNodeId.substring(0, lastSlash) : '/';
  return controller.findNodeById(parentPath);
}

List<TreeNode<FileSystemItem>> getSelectedNodesFromProvider(
  Ref ref,
  ProviderBase<TreeController<FileSystemItem>> controllerProvider, {
  bool topLevelOnly = true,
}) {
  final controller = ref.read(controllerProvider);
  final selected = controller.getSelectedNodesInVisibleOrder(
    topLevelOnly: topLevelOnly,
  );
  if (selected.isNotEmpty) return selected;

  final focusNodeId = controller.selectedNodeId;
  final focusNode = focusNodeId == null
      ? null
      : controller.findNodeById(focusNodeId);
  return focusNode == null ? const [] : [focusNode];
}

// ---------------------------------------------------------------------------
// UI dialogs
// ---------------------------------------------------------------------------

void showEditorSnackBar(BuildContext context, String message) {
  showIdeSuccess(context, message);
}

Future<bool> showDeviceNotReadyDialog(
  BuildContext context, {
  required String operation,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const UseText(I18nKey.dialogDeviceNotReadyTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translateForWidget(
                ref,
                I18nKey.dialogDeviceNotReadyOperation,
              ).replaceAll('{operation}', operation),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: UseText(
                I18nKey.dialogDeviceNotReadyReason,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onErrorContainer,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const UseText(
              I18nKey.dialogDeviceNotReadyHint,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const UseText(I18nKey.dialogSendCtrlC),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

Future<bool> showDiffConfirmDialog(
  BuildContext context, {
  required DiffInfo diff,
  required String targetPath,
  required bool isUpload,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final action = translateForWidget(
          ref,
          isUpload ? I18nKey.dialogUploadAction : I18nKey.dialogDownloadAction,
        );
        return AlertDialog(
          icon: const Icon(Icons.difference),
          title: UseText(
            isUpload
                ? I18nKey.dialogConfirmUpload
                : I18nKey.dialogConfirmDownload,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translateForWidget(ref, I18nKey.dialogDiffTarget)
                    .replaceAll('{action}', action)
                    .replaceAll('{path}', targetPath),
              ),
              const SizedBox(height: 8),
              Text(
                translateForWidget(ref, I18nKey.dialogDiffSummary)
                    .replaceAll('{add}', diff.addCount.toString())
                    .replaceAll('{remove}', diff.removeCount.toString()),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      diff.unifiedLines.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const UseText(I18nKey.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: UseText(
                isUpload
                    ? I18nKey.dialogUploadAction
                    : I18nKey.dialogDownloadAction,
              ),
            ),
          ],
        );
      },
    ),
  );
  return result ?? false;
}

Future<FileConflictAction> showFileConflictDialog(
  BuildContext context, {
  required String sourcePath,
  required String targetPath,
  required bool isUpload,
  bool canShowDiff = false,
}) async {
  final result = await showDialog<FileConflictAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: UseText(
          isUpload
              ? I18nKey.dialogUploadConflict
              : I18nKey.dialogDownloadConflict,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translateForWidget(
                ref,
                I18nKey.dialogConflictTarget,
              ).replaceAll('{path}', targetPath),
            ),
            const SizedBox(height: 8),
            Text(
              translateForWidget(
                ref,
                I18nKey.dialogConflictSource,
              ).replaceAll('{path}', sourcePath),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.cancel),
            child: const UseText(I18nKey.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.skip),
            child: const UseText(I18nKey.dialogSkip),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.skipAll),
            child: const UseText(I18nKey.dialogSkipAll),
          ),
          if (canShowDiff)
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, FileConflictAction.showDiff),
              icon: const Icon(Icons.difference, size: 18),
              label: const UseText(I18nKey.dialogShowDiff),
            ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, FileConflictAction.overwriteAll),
            child: const UseText(I18nKey.dialogOverwriteAll),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.overwrite),
            child: const UseText(I18nKey.dialogOverwrite),
          ),
        ],
      ),
    ),
  );
  return result ?? FileConflictAction.cancel;
}

Future<bool> confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const UseText(I18nKey.dialogDeleteItemTitle),
        content: Text(
          translateForWidget(
            ref,
            I18nKey.dialogDeleteItemMessage,
          ).replaceAll('{name}', name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const UseText(I18nKey.fileActionDelete),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';

/// Builds a [SyncTreeSnapshot] from a local directory tree.
///
/// Pure host-side scanning: hidden/VCS noise (`.git`, `.dart_tool`,
/// `build`, `node_modules`, `__pycache__`) is skipped because syncing them to a
/// MicroPython board would either fail or waste its small filesystem.
Future<SyncTreeSnapshot> scanLocalWorkspace(
  String rootPath, {
  Set<String> ignoredDirectories = defaultSyncIgnoredDirectories,
  int maxFiles = 5000,
}) async {
  final root = Directory(rootPath);
  if (!await root.exists()) {
    return SyncTreeSnapshot(
      files: const {},
      directories: const {},
      root: rootPath,
    );
  }

  final files = <String, SyncFileInfo>{};
  final directories = <String>{};

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relative = normalizeSyncRelativePath(
      path.relative(entity.path, from: rootPath),
    );
    if (relative.isEmpty) continue;
    if (_isIgnoredSyncPath(relative, ignoredDirectories)) continue;
    if (files.length >= maxFiles) break;

    if (entity is Directory) {
      directories.add(relative);
    } else if (entity is File) {
      try {
        final stat = await entity.stat();
        files[relative] = SyncFileInfo(
          relativePath: relative,
          size: stat.size,
          modified: stat.modified,
        );
      } on FileSystemException catch (error) {
        // A file we cannot stat cannot be compared; skipping it is better than
        // aborting the whole plan, but it must be visible in logs.
        debugPrint(
          '[sync] skipping unreadable local file ${entity.path}: $error',
        );
      }
    }
  }
  return SyncTreeSnapshot(
    files: files,
    directories: directories,
    root: rootPath,
  );
}

/// Directories excluded from a project sync by default.
const Set<String> defaultSyncIgnoredDirectories = {
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
  '__pycache__',
  '.DS_Store',
};

bool _isIgnoredSyncPath(String relativePath, Set<String> ignored) {
  final segments = relativePath.split('/');
  for (final segment in segments) {
    if (ignored.contains(segment)) return true;
  }
  return false;
}

/// Scans the board side into a [SyncTreeSnapshot].
///
/// Uses a single `os.ilistdir` walk with `os.stat` metadata; the metadata is
/// optional on the device, and a port that cannot provide mtime leaves the
/// values `null` so the plan falls back to size-only comparison.
Future<SyncTreeSnapshot> scanBoardWorkspace(
  BoardFileOps ops, {
  String boardRoot = '/',
}) async {
  final entries = await ops.lisFolderRecursive(
    path: boardRoot,
    includeMetadata: true,
  );
  final files = <String, SyncFileInfo>{};
  final directories = <String>{};
  final normalizedRoot = ops.normalizeBoardPath(boardRoot);

  for (final entry in entries) {
    final relative = normalizeSyncRelativePath(
      BoardFileOps.boardPath.relative(entry.path, from: normalizedRoot),
    );
    if (relative.isEmpty) continue;
    if (entry.isFolder) {
      directories.add(relative);
      continue;
    }
    files[relative] = SyncFileInfo(
      relativePath: relative,
      size: entry.size,
      modified: entry.modified,
    );
  }
  return SyncTreeSnapshot(
    files: files,
    directories: directories,
    root: normalizedRoot,
  );
}

/// Builds a local<->board plan for the given roots.
///
/// Kept as a standalone function so the preview and the executor share exactly
/// the same diff, and so the pure [buildSyncPlan] stays testable without a
/// device.
Future<BoardSyncPlan> buildWorkspaceSyncPlan({
  required BoardFileOps ops,
  required String localRoot,
  String boardRoot = '/',
  SyncTimestampPolicy policy = SyncTimestampPolicy.sizeAndMtime,
}) async {
  final local = await scanLocalWorkspace(localRoot);
  final board = await scanBoardWorkspace(ops, boardRoot: boardRoot);
  return buildSyncPlan(local: local, board: board, policy: policy);
}

// ---------------------------------------------------------------------------
// Executor
// ---------------------------------------------------------------------------

/// Result of one executed sync.
class BoardSyncExecutionResult {
  const BoardSyncExecutionResult({
    required this.uploaded,
    required this.downloaded,
    required this.skipped,
    required this.failed,
    required this.cancelled,
    this.error,
  });

  final int uploaded;
  final int downloaded;
  final int skipped;
  final List<BoardSyncEntryFailure> failed;
  final bool cancelled;

  /// First fatal error, if execution aborted.
  final Object? error;

  int get transferred => uploaded + downloaded;

  bool get hasFailures => failed.isNotEmpty;

  String get summary =>
      '已上传 $uploaded 个、下载 $downloaded 个、跳过 $skipped 个'
      '${failed.isEmpty ? '' : '、失败 ${failed.length} 个'}'
      '${cancelled ? '（已取消）' : ''}';
}

/// One file that failed during execution.
class BoardSyncEntryFailure {
  const BoardSyncEntryFailure({required this.entry, required this.error});

  final BoardSyncEntry entry;
  final Object error;
}

/// Executes a [BoardSyncPlan] using the existing upload/download paths.
///
/// Rules that keep the device usable:
/// * the cancellation token is checked at every file boundary, so a cancel
///   never interrupts a write in progress (no CTRL-C, no aborted transaction);
/// * uploads go through [BoardFileOps.writeFileBytesWithProgress] and downloads
///   through [BoardFileOps.getFileBytesWithProgress], i.e. exactly the paths
///   the rest of the file page already uses;
/// * the plan's directory sets are created before the first file so a nested
///   tree does not fail halfway.
class BoardSyncExecutor {
  BoardSyncExecutor({required this.ops, required this.progress});

  /// File I/O against the active device; also gives access to the repository
  /// without threading a `Ref` through the UI layer.
  final BoardFileOps ops;

  /// Progress sink shared with the rest of the file page.
  final FileTransferProgressNotifier progress;

  Future<BoardSyncExecutionResult> execute({
    required BoardSyncPlan plan,
    required String localRoot,
    FileTransferCancelToken? cancel,
    Set<String>? selectedPaths,
    bool overwrite = true,
  }) async {
    final selected = selectedPaths;
    final entries = plan.actionable
        .where(
          (entry) => selected == null || selected.contains(entry.relativePath),
        )
        .toList(growable: false);

    progress.start(
      direction: FileTransferDirection.upload,
      scope: FileTransferScope.folder,
      totalFiles: entries.length,
      message: '正在同步本地工作区与设备…',
    );
    // `start()` publishes a fresh token. The executor must read that one (or
    // the caller's explicit token) instead of a token captured before the call,
    // otherwise the progress bar's cancel button would flip a flag nobody reads.
    final token = cancel ?? progress.beginCancelToken();

    var uploaded = 0;
    var downloaded = 0;
    var skipped = 0;
    var cancelled = false;
    final failures = <BoardSyncEntryFailure>[];

    try {
      final boardDirectories = plan.requiredBoardDirectories;
      for (final directory in boardDirectories) {
        final target = ops.normalizeBoardPath('/$directory');
        try {
          await ops.createFolder(target);
        } catch (_) {
          // Existing directories raise; verify instead of assuming failure.
          if (!await ops.boardFolderExists(target)) rethrow;
        }
      }

      for (var index = 0; index < entries.length; index++) {
        if (token.isCancelled) {
          cancelled = true;
          break;
        }
        final entry = entries[index];
        try {
          switch (entry.action) {
            case BoardSyncAction.uploadNew:
            case BoardSyncAction.uploadChanged:
              final localFile = File(path.join(localRoot, entry.relativePath));
              final bytes = await localFile.readAsBytes();
              await ops.writeFileBytesWithProgress(
                ops.normalizeBoardPath('/${entry.relativePath}'),
                bytes,
                currentFile: entry.relativePath,
                index: index + 1,
                totalFiles: entries.length,
              );
              uploaded++;
            case BoardSyncAction.downloadNew:
            case BoardSyncAction.downloadChanged:
              final bytes = await ops.getFileBytesWithProgress(
                ops.normalizeBoardPath('/${entry.relativePath}'),
                currentFile: entry.relativePath,
                index: index + 1,
                totalFiles: entries.length,
              );
              final localFile = File(path.join(localRoot, entry.relativePath));
              await localFile.parent.create(recursive: true);
              await localFile.writeAsBytes(bytes);
              downloaded++;
            case BoardSyncAction.unchanged:
            case BoardSyncAction.conflict:
              skipped++;
          }
        } catch (error) {
          // One failed file must not abort the whole sync: the device stays
          // usable and the rest of the plan can still be applied.
          debugPrint('[sync] failed ${entry.relativePath}: $error');
          failures.add(BoardSyncEntryFailure(entry: entry, error: error));
        }
      }

      if (cancelled) {
        progress.cancelledByUser(message: '同步已取消');
      } else if (failures.isEmpty) {
        progress.complete(message: '同步完成');
      } else {
        progress.fail('同步完成但有 ${failures.length} 个文件失败');
      }
      return BoardSyncExecutionResult(
        uploaded: uploaded,
        downloaded: downloaded,
        skipped: skipped,
        failed: failures,
        cancelled: cancelled,
      );
    } catch (error) {
      progress.fail('同步失败：$error');
      return BoardSyncExecutionResult(
        uploaded: uploaded,
        downloaded: downloaded,
        skipped: skipped,
        failed: failures,
        cancelled: cancelled,
        error: error,
      );
    }
  }
}

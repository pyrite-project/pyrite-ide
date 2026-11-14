import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/device/board_sync_plan.dart';
import 'package:pyrite_ide/core/services/device/file_hash.dart';
import 'package:pyrite_ide/core/services/device/sync_ignore.dart';
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
///
/// The workspace's `.pyrsyncignore` is read here rather than inside
/// [scanLocalWorkspace]: the ignored paths must stay in the snapshot so the
/// preview can list them in a collapsed group, they are only flagged as
/// "not selected by default".
Future<BoardSyncPlan> buildWorkspaceSyncPlan({
  required BoardFileOps ops,
  required String localRoot,
  String boardRoot = '/',
  SyncTimestampPolicy policy = SyncTimestampPolicy.sizeAndMtime,
  I18nTranslate? translate,
}) async {
  final local = await scanLocalWorkspace(localRoot);
  final ignore = await loadSyncIgnoreRules(localRoot);
  final board = await scanBoardWorkspace(ops, boardRoot: boardRoot);
  return buildSyncPlan(
    local: local,
    board: board,
    policy: policy,
    ignore: ignore,
    translate: translate,
  );
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
    this.translate,
  });

  final int uploaded;
  final int downloaded;
  final int skipped;
  final List<BoardSyncEntryFailure> failed;
  final bool cancelled;

  /// First fatal error, if execution aborted.
  final Object? error;

  /// Localized the [summary] text; null keeps the fallback language.
  final I18nTranslate? translate;

  int get transferred => uploaded + downloaded;

  bool get hasFailures => failed.isNotEmpty;

  String get summary {
    final tr = translate ?? fallbackTranslate;
    return tr(I18nKey.devicesSyncRunSummary, {
          'uploaded': '$uploaded',
          'downloaded': '$downloaded',
          'skipped': '$skipped',
        }) +
        (failed.isEmpty
            ? ''
            : tr(I18nKey.devicesSyncRunSummaryFailed, {
                'count': '${failed.length}',
              })) +
        (cancelled ? tr(I18nKey.devicesSyncRunSummaryCancelled) : '');
  }
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
/// * entries whose board copy already holds the same bytes (same size and
///   CRC-32) are counted as skipped instead of being re-transferred, which is
///   what keeps an mtime-driven plan from rewriting unchanged files;
/// * uploads go through [BoardFileOps.writeFileBytesWithProgress] and downloads
///   through [BoardFileOps.getFileBytesWithProgress], i.e. exactly the paths
///   the rest of the file page already uses;
/// * the plan's directory sets are created before the first file so a nested
///   tree does not fail halfway.
class BoardSyncExecutor {
  BoardSyncExecutor({required this.ops, required this.progress, this.translate})
    : _tr = translate ?? fallbackTranslate;

  /// File I/O against the active device; also gives access to the repository
  /// without threading a `Ref` through the UI layer.
  final BoardFileOps ops;

  /// Progress sink shared with the rest of the file page.
  final FileTransferProgressNotifier progress;

  /// Localized the progress/summary text; null keeps the fallback language.
  final I18nTranslate? translate;

  final I18nTranslate _tr;

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
      message: _tr(I18nKey.devicesSyncRunning),
    );
    // `start()` publishes a fresh token. The executor must read that one (or
    // the caller's explicit token) instead of a token captured before the call,
    // otherwise the progress bar's cancel button would flip a flag nobody reads.
    final token = cancel ?? progress.beginCancelToken();
    final boardChecksums = token.isCancelled
        ? const <String, int>{}
        : await _boardChecksumsFor(entries);

    var uploaded = 0;
    var downloaded = 0;
    var skipped = 0;
    var cancelled = false;
    final failures = <BoardSyncEntryFailure>[];

    try {
      // Only the rows about to be transferred may create directories:
      // `boardDirectoriesForUploads` walks the selection, so an ignored path
      // the user left unticked cannot leave an empty folder on the board.
      // The set collects parents deepest-first, and the device's `os.mkdir`
      // does not create missing parents: creating shallowest-first keeps
      // nested trees from failing with ENOENT.
      final boardDirectories = boardDirectoriesForUploads(entries).toList()
        ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));
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
          // The relative path on the download side comes from the board's own
          // listing, i.e. from outside this process. `normalizeSyncRelativePath`
          // keeps a leading `..`, so without this check a board that reports
          // `../../.bashrc` would have us write outside the workspace.
          if (!path.isWithin(
            localRoot,
            path.normalize(path.join(localRoot, entry.relativePath)),
          )) {
            throw StateError(
              'refusing to write outside the workspace: ${entry.relativePath}',
            );
          }
          switch (entry.action) {
            case BoardSyncAction.uploadNew:
            case BoardSyncAction.uploadChanged:
              final localFile = File(path.join(localRoot, entry.relativePath));
              final bytes = await localFile.readAsBytes();
              if (_boardCopyMatches(boardChecksums, entry, bytes)) {
                skipped++;
                debugPrint('[sync] skipping identical ${entry.relativePath}');
                continue;
              }
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
              final boardPath = ops.normalizeBoardPath(
                '/${entry.relativePath}',
              );
              final boardChecksum = boardChecksums[boardPath];
              if (boardChecksum != null) {
                final localChecksum = await crc32OfFile(
                  path.join(localRoot, entry.relativePath),
                );
                if (localChecksum == boardChecksum) {
                  skipped++;
                  debugPrint('[sync] skipping identical ${entry.relativePath}');
                  continue;
                }
              }
              final bytes = await ops.getFileBytesWithProgress(
                boardPath,
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
        progress.cancelledByUser(message: _tr(I18nKey.devicesSyncCancelled));
      } else if (failures.isEmpty) {
        progress.complete(message: _tr(I18nKey.devicesSyncDone));
      } else {
        progress.fail(
          _tr(I18nKey.devicesSyncDoneWithFailures, {
            'count': '${failures.length}',
          }),
        );
      }
      return BoardSyncExecutionResult(
        uploaded: uploaded,
        downloaded: downloaded,
        skipped: skipped,
        failed: failures,
        cancelled: cancelled,
        translate: translate,
      );
    } catch (error) {
      progress.fail(_tr(I18nKey.devicesSyncFailed, {'error': '$error'}));
      return BoardSyncExecutionResult(
        uploaded: uploaded,
        downloaded: downloaded,
        skipped: skipped,
        failed: failures,
        cancelled: cancelled,
        error: error,
        translate: translate,
      );
    }
  }

  /// CRC-32 checksums of the board copies that may already match local files.
  ///
  /// Only entries with both sides reporting the same size can be identical —
  /// same content implies same length — which keeps the device-side reads
  /// limited to files worth comparing. An empty map (device without usable
  /// `binascii.crc32`, listing failure, ...) simply disables the skip.
  Future<Map<String, int>> _boardChecksumsFor(
    List<BoardSyncEntry> entries,
  ) async {
    final candidates = <String>{};
    for (final entry in entries) {
      final action = entry.action;
      if (action != BoardSyncAction.uploadChanged &&
          action != BoardSyncAction.downloadChanged) {
        continue;
      }
      final localSize = entry.local?.size;
      final boardSize = entry.board?.size;
      if (localSize == null || localSize != boardSize) continue;
      candidates.add(ops.normalizeBoardPath('/${entry.relativePath}'));
    }
    return ops.boardFileHashes(candidates);
  }

  /// Whether the board copy of [entry] already holds exactly [bytes].
  ///
  /// A checksum is only present when both sides reported the same size, so a
  /// match here means "same length and same CRC-32".
  bool _boardCopyMatches(
    Map<String, int> boardChecksums,
    BoardSyncEntry entry,
    List<int> bytes,
  ) {
    final boardChecksum =
        boardChecksums[ops.normalizeBoardPath('/${entry.relativePath}')];
    return boardChecksum != null && boardChecksum == crc32OfBytes(bytes);
  }
}

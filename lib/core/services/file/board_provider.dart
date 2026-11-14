import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/device/file_hash.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/board_tree.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:super_tree/super_tree.dart';
import 'package:tabbed_view/tabbed_view.dart';

class BoardNotifier {
  final Ref ref;
  late final BoardFileOps ops;
  late final BoardTransfer transfer;

  BoardNotifier(this.ref) {
    ops = BoardFileOps(ref);
    transfer = BoardTransfer(ref, ops);
  }

  /// Resolves the local mirror file for a board path in the download paths.
  ///
  /// Indirection rather than a direct [getLocalFile] call so a widget test can
  /// drive a download without waiting on real file I/O, which the fake-async
  /// zone widget tests run in cannot complete on its own.
  @visibleForTesting
  Future<File> Function(String boardPath) mirrorFileReader = getLocalFile;

  TreeNode<FileSystemItem>? getFocusFileNode() {
    return getFocusFileNodeFromProvider(
      ref,
      boardFileTreeViewControllerProvider,
    );
  }

  TreeNode<FileSystemItem>? getFocusFolderNode() {
    return getFocusFolderNodeFromProvider(
      ref,
      boardFileTreeViewControllerProvider,
    );
  }

  List<TreeNode<FileSystemItem>> getSelectedNodes({bool topLevelOnly = true}) {
    return getSelectedNodesFromProvider(
      ref,
      boardFileTreeViewControllerProvider,
      topLevelOnly: topLevelOnly,
    );
  }

  Future<void> deleteSelectedBoardItems(BuildContext context) async {
    final nodes = getSelectedNodes();
    if (nodes.isEmpty) {
      showEditorSnackBar(
        context,
        translateWithReplacements(ref, I18nKey.fileMessageSelectBoardItem),
      );
      return;
    }

    for (final node in nodes) {
      if (node.data is FolderItem) {
        await ops.deleteFolder(node.id);
      } else {
        await ops.deleteFile(node.id);
      }
    }
    ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
    if (context.mounted) {
      showEditorSnackBar(
        context,
        translateWithReplacements(ref, I18nKey.fileMessageDeletedBoardItems, {
          'count': '${nodes.length}',
        }),
      );
    }
  }

  Future<void> moveBoardNodes(
    BuildContext context,
    List<TreeNode<FileSystemItem>> nodes,
    String targetFolder,
  ) async {
    final normalizedTargetFolder = ops.normalizeBoardPath(targetFolder);
    final movableNodes = nodes
        .where(
          (node) =>
              ops.normalizeBoardPath(BoardFileOps.boardPath.dirname(node.id)) !=
              normalizedTargetFolder,
        )
        .toList(growable: false);
    if (movableNodes.isEmpty) return;
    FileConflictAction? conflictPolicy;
    var moved = 0;
    var skipped = 0;
    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.move,
          scope: movableNodes.any((node) => node.data is FolderItem)
              ? FileTransferScope.folder
              : FileTransferScope.file,
          totalFiles: movableNodes.length,
          message: translateWithReplacements(
            ref,
            I18nKey.fileTransferPrepareMoveBoardFile,
          ),
        );

    try {
      for (var i = 0; i < movableNodes.length; i++) {
        final node = movableNodes[i];
        final sourcePath = ops.normalizeBoardPath(node.id);
        final targetPath = normalizedTargetFolder == '/'
            ? '/${BoardFileOps.boardPath.basename(sourcePath)}'
            : BoardFileOps.boardPath.join(
                normalizedTargetFolder,
                BoardFileOps.boardPath.basename(sourcePath),
              );
        if (sourcePath == targetPath) {
          skipped++;
          continue;
        }
        if (node.data is FolderItem &&
            ops.isBoardPathInside(normalizedTargetFolder, sourcePath)) {
          if (context.mounted) {
            showEditorSnackBar(
              context,
              translateWithReplacements(
                ref,
                I18nKey.fileMessageCannotMoveFolderIntoSelf,
              ),
            );
          }
          skipped++;
          continue;
        }

        final targetExists = await ops.boardPathExistsAny(targetPath);
        if (targetExists) {
          if (!context.mounted) return;
          final action = await resolveConflict(
            context,
            policy: conflictPolicy,
            sourcePath: sourcePath,
            targetPath: targetPath,
            isUpload: true,
          );
          switch (action) {
            case FileConflictAction.cancel:
              if (context.mounted) {
                showEditorSnackBar(
                  context,
                  translateWithReplacements(
                    ref,
                    I18nKey.fileMessageCanceledMove,
                  ),
                );
              }
              return;
            case FileConflictAction.showDiff:
              if (context.mounted) {
                showEditorSnackBar(
                  context,
                  translateWithReplacements(
                    ref,
                    I18nKey.fileMessageCannotShowMoveDiff,
                  ),
                );
              }
              return;
            case FileConflictAction.skip:
              skipped++;
              continue;
            case FileConflictAction.skipAll:
              conflictPolicy = FileConflictAction.skipAll;
              skipped++;
              continue;
            case FileConflictAction.overwriteAll:
              conflictPolicy = FileConflictAction.overwriteAll;
              break;
            case FileConflictAction.overwrite:
              break;
          }
          await ops.deleteBoardPathAny(targetPath);
        }

        ref
            .read(fileTransferProgressProvider.notifier)
            .startFile(
              file: sourcePath,
              index: i + 1,
              totalFiles: movableNodes.length,
              bytesTotal: 0,
            );
        await ops.move(sourcePath, targetPath);
        // A board tab holds both the remote path and the local mirror it was
        // read from; both identities have to follow the move, or the next
        // save writes the old remote path and the mirror is orphaned.
        await ref
            .read(tabbedViewControllerProvider.notifier)
            .renameBoardOpenPath(sourcePath, targetPath);
        moved++;
      }

      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(
            message: translateWithReplacements(
              ref,
              I18nKey.fileMessageMoveComplete,
              {'done': '$moved', 'skipped': '$skipped'},
            ),
          );
      if (context.mounted) {
        showEditorSnackBar(
          context,
          translateWithReplacements(ref, I18nKey.fileMessageMoveComplete, {
            'done': '$moved',
            'skipped': '$skipped',
          }),
        );
      }
    } catch (error) {
      ref
          .read(fileTransferProgressProvider.notifier)
          .fail(
            translateWithReplacements(ref, I18nKey.fileMessageMoveFailed, {
              'error': '$error',
            }),
          );
      rethrow;
    }
  }

  Future<void> downloadSelectedBoardItems(
    BuildContext context, {
    String? localFolderPath,
  }) async {
    final nodes = getSelectedNodes();
    if (nodes.isEmpty) {
      showEditorSnackBar(
        context,
        translateWithReplacements(ref, I18nKey.fileMessageSelectBoardItem),
      );
      return;
    }

    final localWorkspace = ref.read(fileProvider);
    if (localWorkspace == null) {
      showEditorSnackBar(
        context,
        translateWithReplacements(ref, I18nKey.fileMessageOpenLocalProject),
      );
      return;
    }
    showDeviceRequestPending(context, ref);

    final localFolderTarget =
        localFolderPath ??
        ref.read(fileProvider.notifier).getFocusFolderNode()?.id;
    final targetFolder = localFolderTarget ?? localWorkspace.path;
    final progressNotifier = ref.read(fileTransferProgressProvider.notifier);
    final cancelToken = progressNotifier.beginCancelToken();
    FileConflictAction? conflictPolicy;
    var downloaded = 0;
    var skipped = 0;
    final transferredFiles = <String>[];
    final transferredFolders = <String>[];

    try {
      for (var i = 0; i < nodes.length; i++) {
        throwIfTransferCancelled(cancelToken);
        final node = nodes[i];
        final targetPath = path.join(
          targetFolder,
          BoardFileOps.boardPath.basename(node.id),
        );
        final exists = node.data is FolderItem
            ? await Directory(targetPath).exists()
            : await File(targetPath).exists();
        if (exists) {
          if (node.data is! FolderItem &&
              await _boardFileMatchesLocal(node.id, targetPath)) {
            // Same bytes on both sides: neither a dialog nor a transfer needed.
            skipped++;
            continue;
          }
          if (!context.mounted) return;
          final canShowDiff = node.data is! FolderItem;
          final action = await resolveConflict(
            context,
            policy: conflictPolicy,
            sourcePath: node.id,
            targetPath: targetPath,
            isUpload: false,
            canShowDiff: canShowDiff,
          );
          switch (action) {
            case FileConflictAction.cancel:
              if (context.mounted) {
                showEditorSnackBar(
                  context,
                  translateWithReplacements(
                    ref,
                    I18nKey.fileMessageCanceledDownload,
                  ),
                );
              }
              return;
            case FileConflictAction.showDiff:
              if (!canShowDiff) {
                if (context.mounted) {
                  showEditorSnackBar(
                    context,
                    translateWithReplacements(
                      ref,
                      I18nKey.fileMessageCannotShowFolderDiff,
                    ),
                  );
                }
                return;
              }
              if (!context.mounted) return;
              final shown = await _showDownloadDiff(
                context,
                boardPath: node.id,
                localPath: targetPath,
              );
              if (!shown) {
                if (context.mounted) {
                  showEditorSnackBar(
                    context,
                    translateWithReplacements(
                      ref,
                      I18nKey.fileMessageCannotShowDiff,
                    ),
                  );
                }
              }
              return;
            case FileConflictAction.skip:
              skipped++;
              continue;
            case FileConflictAction.skipAll:
              conflictPolicy = FileConflictAction.skipAll;
              skipped++;
              continue;
            case FileConflictAction.overwriteAll:
              conflictPolicy = FileConflictAction.overwriteAll;
              break;
            case FileConflictAction.overwrite:
              break;
          }
        }

        if (node.data is FolderItem) {
          skipped += await transfer.downloadFolder(
            node.id,
            targetPath,
            cancel: cancelToken,
          );
          transferredFolders.add(targetPath);
        } else {
          ref
              .read(fileTransferProgressProvider.notifier)
              .start(
                direction: FileTransferDirection.download,
                scope: FileTransferScope.file,
                totalFiles: nodes.length,
                message: translateWithReplacements(
                  ref,
                  I18nKey.fileTransferPrepareDownloadFile,
                ),
              );
          final bytes = await ops.getFileBytesWithProgress(
            node.id,
            currentFile: node.id,
            index: i + 1,
            totalFiles: nodes.length,
          );
          final file = File(targetPath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          transferredFiles.add(targetPath);
        }
        downloaded++;
      }
    } on FileTransferCancelledException {
      progressNotifier.cancelledByUser();
      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
      if (context.mounted) {
        showEditorSnackBar(
          context,
          '${translate(ref, I18nKey.fileMessageCanceledDownload)}'
          '${translateWithReplacements(ref, I18nKey.fileTransferProgressSuffix, {'done': '$downloaded', 'skipped': '$skipped'})}',
        );
      }
      return;
    } finally {
      ref
          .read(tabbedViewControllerProvider.notifier)
          .warnOpenFilesOverwritten(
            boardFiles: false,
            filePaths: transferredFiles,
            folderPaths: transferredFolders,
          );
    }

    ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    ref
        .read(fileTransferProgressProvider.notifier)
        .complete(
          message: translateWithReplacements(
            ref,
            I18nKey.fileMessageDownloadComplete,
            {'done': '$downloaded', 'skipped': '$skipped'},
          ),
        );
    if (context.mounted) {
      showEditorSnackBar(
        context,
        translateWithReplacements(ref, I18nKey.fileMessageDownloadComplete, {
          'done': '$downloaded',
          'skipped': '$skipped',
        }),
      );
    }
  }

  /// Whether the board file and the local file hold the same bytes.
  ///
  /// Uses a device-side CRC-32 so identical files do not have to be
  /// transferred; `false` on any probe failure, which routes the caller
  /// through the normal conflict flow instead.
  Future<bool> _boardFileMatchesLocal(
    String boardPath,
    String localPath,
  ) async {
    final localChecksum = await crc32OfFile(localPath);
    if (localChecksum == null) return false;
    final checksums = await ops.boardFileHashes([boardPath]);
    final boardChecksum = checksums[ops.normalizeBoardPath(boardPath)];
    return boardChecksum != null && boardChecksum == localChecksum;
  }

  Future<bool> _showDownloadDiff(
    BuildContext context, {
    required String boardPath,
    required String localPath,
  }) async {
    late final String content;
    late final String originContent;
    try {
      content = await ops.getFileContent(boardPath);
      originContent = await File(localPath).readAsString();
    } catch (_) {
      return false;
    }
    if (originContent == content) return false;

    final diff = computeDiff(originContent, content);
    if (!context.mounted) return false;
    final correspondingFile = await openFile(context, boardPath);
    if (correspondingFile == null) return false;

    final controller = ref
        .read(editorControllerMapProvider.notifier)
        .getSelectedController();
    controller?.setGitDiffDecorations(
      addedRanges: diff.addedRanges,
      removedRanges: diff.removedRanges,
    );
    // The preview is a look at what would be written locally, not a scratch
    // buffer; EditCore restores editability when the pending state is
    // confirmed or cancelled.
    controller?.readOnly = true;
    revealFirstDifference(controller, diff);

    final correspondingFilePath = (await mirrorFileReader(boardPath)).path;
    final provider = pendingDownloadProviderMap.putIfAbsent(
      correspondingFilePath,
      () => StateProvider<PendingDownload?>((ref) => null),
    );
    ref.read(provider.notifier).state = PendingDownload(
      diff: diff,
      boardPath: boardPath,
      localPath: localPath,
      correspondingPath: correspondingFile.path,
      content: content,
    );

    if (context.mounted && !ResponsiveBreakpoints.of(context).isDesktop) {
      context.go('/editor');
    }
    return true;
  }

  Future<File?> openFile(BuildContext context, String id) async {
    ref.read(boardFileTreeViewControllerProvider).setSelectedNodeId(id);
    final node = ref.read(boardFileTreeViewControllerProvider).findNodeById(id);
    if (node == null || node.data is! FileItem) return null;
    showDeviceRequestPending(context, ref);
    final file = await mirrorFileReader(node.id);
    final content = await ops.getFileContent(id);
    await file.writeAsString(content);
    if (context.mounted) {
      await ref
          .read(tabbedViewControllerProvider.notifier)
          .openFile(context, file: file, isBoardFile: true, boardFilePath: id);
    }
    return file;
  }

  Future<void> downloadSelectedBoardItem(
    BuildContext context, {
    TabData? selectedTab,
  }) async {
    final selectedFile = getFocusFileNode();
    final selectedFolder = getFocusFolderNode();
    final selected = selectedFile ?? selectedFolder;
    final localWorkspace = ref.read(fileProvider);
    if (selected == null && selectedTab == null) {
      showEditorSnackBar(
        context,
        translateWithReplacements(ref, I18nKey.fileMessageSelectBoardItem),
      );
      return;
    }
    if (localWorkspace == null) {
      showEditorSnackBar(
        context,
        translateWithReplacements(ref, I18nKey.fileMessageOpenLocalProject),
      );
      return;
    }

    if (selected?.data is FileItem || selectedTab != null) {
      final boardPath = selected?.id ?? selectedTab?.value.filePath;
      final content = await ops.getFileContent(boardPath);
      final correspondingFilePath = (await mirrorFileReader(boardPath)).path;

      if ((ref.read(editorControllerMapProvider)[correspondingFilePath]?.text !=
              null) &&
          (content !=
              ref
                  .read(editorControllerMapProvider)[correspondingFilePath]!
                  .text)) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.file_download_outlined),
            title: const UseText(I18nKey.dialogBoardContentMismatchTitle),
            content: Text(
              translate(
                ref,
                I18nKey.dialogContentMismatchMessage,
              ).replaceAll('{path}', boardPath ?? ''),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const UseText(I18nKey.dialogCancelUpload),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext, false);
                  // The dialog compared the document at
                  // [correspondingFilePath], so that is the tab to save. The
                  // download below may only start once its bytes are on disk.
                  if (!await ref
                      .read(fileProvider.notifier)
                      .saveTabForPath(correspondingFilePath)) {
                    return;
                  }
                  if (!context.mounted) return;
                  await _doDownloadBoardItem(
                    context,
                    selected,
                    selectedTab,
                    localWorkspace,
                  );
                },
                child: const UseText(I18nKey.dialogEditorContent),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () async {
                  ref
                          .read(
                            editorControllerMapProvider,
                          )[correspondingFilePath]
                          ?.text =
                      content;
                  Navigator.pop(dialogContext, false);
                  if (!await ref
                      .read(fileProvider.notifier)
                      .saveTabForPath(correspondingFilePath)) {
                    return;
                  }
                  if (!context.mounted) return;
                  await _doDownloadBoardItem(
                    context,
                    selected,
                    selectedTab,
                    localWorkspace,
                  );
                },
                child: const UseText(I18nKey.dialogActualContent),
              ),
            ],
          ),
        );
      } else {
        if (!context.mounted) return;
        _doDownloadBoardItem(context, selected, selectedTab, localWorkspace);
      }
    } else {
      if (!context.mounted) return;
      _doDownloadBoardItem(context, selected, selectedTab, localWorkspace);
    }
  }

  Future<void> _doDownloadBoardItem(
    BuildContext context,
    TreeNode<FileSystemItem>? selected,
    TabData? selectedTab,
    Directory localWorkspace,
  ) async {
    final localFolderTarget = ref
        .read(fileProvider.notifier)
        .getFocusFolderNode();
    final sourceName = BoardFileOps.boardPath.basename(
      (selected?.id ?? selectedTab?.value.filePath).toString(),
    );
    final targetPath = localFolderTarget?.id != null
        ? path.join(localFolderTarget!.id, sourceName)
        : path.join(localWorkspace.path, sourceName);

    if (selected?.data is FileItem || selectedTab != null) {
      final filePath = selected?.id ?? selectedTab?.value.filePath;
      final content = await ops.getFileContent(filePath);

      String? originContent;
      if (await File(targetPath).exists()) {
        try {
          originContent = await File(targetPath).readAsString();
        } catch (error) {
          debugPrint(
            '[lib/core/services/file/board_provider.dart] ignored error: $error',
          );
        }
      }
      if (originContent != null && originContent != content) {
        final diff = computeDiff(originContent, content);
        if (ref.read(uploadConfirmStyleProvider) == 'dialog') {
          if (!context.mounted) return;
          final confirmed = await showDiffConfirmDialog(
            context,
            diff: diff,
            targetPath: targetPath,
            isUpload: false,
          );
          if (!confirmed) {
            if (context.mounted) {
              showEditorSnackBar(
                context,
                translateWithReplacements(
                  ref,
                  I18nKey.fileMessageCanceledDownload,
                ),
              );
            }
            return;
          }
        } else {
          if (!context.mounted) return;
          await _showDownloadDiff(
            context,
            boardPath: filePath,
            localPath: targetPath,
          );
          return;
        }
      }

      ref
          .read(fileTransferProgressProvider.notifier)
          .start(
            direction: FileTransferDirection.download,
            scope: FileTransferScope.file,
            totalFiles: 1,
            message: translateWithReplacements(
              ref,
              I18nKey.fileTransferPrepareDownloadFile,
            ),
          );
      Uint8List bytes;
      try {
        bytes = await ops.getFileBytesWithProgress(
          filePath,
          currentFile: filePath,
          index: 1,
          totalFiles: 1,
        );
      } on BoardFileBackendException catch (e) {
        var errorMsg = e.message;
        if (e.message.contains('ENOENT') ||
            e.message.contains('No such file')) {
          errorMsg =
              '$errorMsg\n${translateWithReplacements(ref, I18nKey.fileMessageFilesystemNotMounted)}';
        }
        ref
            .read(fileTransferProgressProvider.notifier)
            .fail(
              translateWithReplacements(
                ref,
                I18nKey.fileMessageDownloadFailed,
                {'error': errorMsg},
              ),
            );
        return;
      }
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      ref
          .read(tabbedViewControllerProvider.notifier)
          .warnOpenFilesOverwritten(boardFiles: false, filePaths: [targetPath]);
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(
            message: translateWithReplacements(
              ref,
              I18nKey.fileMessageDownloadedToLocal,
              {'path': targetPath},
            ),
          );
      if (context.mounted) {
        showEditorSnackBar(
          context,
          translateWithReplacements(ref, I18nKey.fileMessageDownloadedToLocal, {
            'path': targetPath,
          }),
        );
      }
    } else {
      final filePath = selected?.id ?? selectedTab?.value.filePath;
      try {
        await transfer.downloadFolder(filePath, targetPath);
        ref
            .read(tabbedViewControllerProvider.notifier)
            .warnOpenFilesOverwritten(
              boardFiles: false,
              folderPaths: [targetPath],
            );
        ref
            .read(fileTransferProgressProvider.notifier)
            .complete(
              message: translateWithReplacements(
                ref,
                I18nKey.fileMessageDownloadedFolderToLocal,
                {'path': targetPath},
              ),
            );
      } catch (error) {
        ref
            .read(fileTransferProgressProvider.notifier)
            .fail(
              translateWithReplacements(
                ref,
                I18nKey.fileMessageDownloadFailed,
                {'error': '$error'},
              ),
            );
        rethrow;
      }
      if (context.mounted) {
        showEditorSnackBar(
          context,
          translateWithReplacements(
            ref,
            I18nKey.fileMessageDownloadedFolderToLocal,
            {'path': targetPath},
          ),
        );
      }
    }

    ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
  }
}

final boardProvider = Provider<BoardNotifier>(BoardNotifier.new);

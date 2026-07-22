import 'dart:io';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/ui_utils.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_progress.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as utils;
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:super_tree/super_tree.dart';
import 'package:tabbed_view/tabbed_view.dart';

final _boardUploadPath = path.Context(style: path.Style.posix);
final _windowsUploadSourcePath = path.Context(style: path.Style.windows);
final _windowsAbsoluteSourcePath = RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)');

@visibleForTesting
String buildBoardUploadTargetPath({
  required String sourcePath,
  required String? boardFolderPath,
}) {
  final folder = boardFolderPath == null || boardFolderPath.isEmpty
      ? "/"
      : boardFolderPath;
  return _boardUploadPath.join(folder, _localSourceBasename(sourcePath));
}

String _localSourceBasename(String sourcePath) {
  if (_windowsAbsoluteSourcePath.hasMatch(sourcePath)) {
    return _windowsUploadSourcePath.basename(sourcePath);
  }

  return path.basename(sourcePath);
}

class FileNotifier extends StateNotifier<Directory?> {
  final Ref ref;
  FileNotifier(this.ref) : super(null);

  void setDirectory(Directory dir) {
    state = dir;
  }

  Future<Directory?> getDirectory() async {
    final String? path = await getDirectoryPath();
    final Directory? dir;
    if (path != null) {
      dir = Directory(path);
      state = dir;
      return dir;
    } else {
      return null;
    }
  }

  Future<Stream<FileSystemEntity>> getFileList({String? path}) async {
    Stream<FileSystemEntity> datas;
    if (state != null && (path == null || path == state!.path)) {
      datas = state!.list();
    } else {
      if (path != null) {
        datas = Directory(path).list();
      } else {
        datas = Stream.empty();
      }
    }
    return datas;
  }

  Future<void> saveCurrentFile() async {
    final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
    final value = nowTab?.value;
    if (value is TabDataValue && value.type == "file") {
      if (value.isBoardFile == true && value.boardFilePath != null) {
        await ref
            .read(boardProvider.notifier)
            .writeFile(value.boardFilePath!, value.editorController!.text);
        ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      } else {
        await value.file!.writeAsString(value.editorController!.text);
      }
      ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
    }
  }

  void saveCurrentFileAs() async {
    final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
    if (nowTab != null && nowTab.value.type == "file") {
      final bool state = await utils.sysSaveAs(
        nowTab.value.editorController!.text,
      );
      if (state) {
        ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
      }
    }
  }

  Future<String> createFile(String filePath) async {
    final file = File(filePath);
    await file.create();

    final parentDir = path.dirname(filePath);
    final parentNode = ref
        .read(localFileTreeViewControllerProvider)
        .findNodeById(parentDir);

    if (parentNode != null) {
      ref
          .read(localFileTreeViewControllerProvider)
          .addChild(
            parentNode,
            TreeNode(id: filePath, data: FileItem(path.basename(filePath))),
          );
    } else {
      ref
          .read(localFileTreeViewControllerProvider)
          .addRoot(
            TreeNode(id: filePath, data: FileItem(path.basename(filePath))),
          );
    }
    return filePath;
  }

  Future<String> createFolder(String folderPath) async {
    final dir = Directory(folderPath);
    await dir.create();

    final parentDir = path.dirname(folderPath);
    final parentNode = ref
        .read(localFileTreeViewControllerProvider)
        .findNodeById(parentDir);

    if (parentNode != null) {
      ref
          .read(localFileTreeViewControllerProvider)
          .addChild(
            parentNode,
            TreeNode(
              id: folderPath,
              canLoadChildren: true,
              data: FolderItem(path.basename(folderPath)),
            ),
          );
    } else {
      ref
          .read(localFileTreeViewControllerProvider)
          .addRoot(
            TreeNode(
              id: folderPath,
              canLoadChildren: true,
              data: FolderItem(path.basename(folderPath)),
            ),
          );
    }
    return folderPath;
  }

  TreeNode<FileSystemItem>? getFocusFileNode() {
    String focusNodeId =
        ref.read(localFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(localFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FileItem) {
      return focusNode;
    } else {
      return null;
    }
  }

  TreeNode<FileSystemItem>? getFocusFolderNode() {
    String focusNodeId =
        ref.read(localFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(localFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FolderItem) {
      return focusNode;
    } else {
      return ref
          .read(localFileTreeViewControllerProvider)
          .findNodeById(path.dirname(focusNodeId));
    }
  }

  List<TreeNode<FileSystemItem>> getSelectedNodes({bool topLevelOnly = true}) {
    final controller = ref.read(localFileTreeViewControllerProvider);
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

  Future<void> deleteSelectedLocalItems(BuildContext context) async {
    final nodes = getSelectedNodes();
    if (nodes.isEmpty) {
      showEditorSnackBar(context, "先选择一个本地文件或文件夹");
      return;
    }

    for (final node in nodes) {
      if (node.data is FolderItem) {
        await local.deleteDir(node.id);
      } else {
        await local.deleteFile(node.id);
      }
    }
    ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    showEditorSnackBar(context, "已删除 ${nodes.length} 个本地项目");
  }

  Future<void> uploadSelectedLocalItems(
    BuildContext context, {
    String? boardFolderPath,
  }) async {
    final nodes = getSelectedNodes();
    if (nodes.isEmpty) {
      showEditorSnackBar(context, "先选择一个本地文件或文件夹");
      return;
    }

    final boardFolderTarget =
        boardFolderPath ??
        ref.read(boardProvider.notifier).getFocusFolderNode()?.id;
    FileConflictAction? conflictPolicy;
    var uploaded = 0;
    var skipped = 0;

    try {
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final targetPath = buildBoardUploadTargetPath(
          sourcePath: node.id,
          boardFolderPath: boardFolderTarget,
        );
        final exists = await _boardPathExists(
          targetPath,
          node.data is FolderItem,
        );
        if (exists) {
          final canShowDiff = node.data is! FolderItem;
          final action = await _resolveConflict(
            context,
            policy: conflictPolicy,
            sourcePath: node.id,
            targetPath: targetPath,
            isUpload: true,
            canShowDiff: canShowDiff,
          );
          switch (action) {
            case FileConflictAction.cancel:
              showEditorSnackBar(context, "已取消上传");
              return;
            case FileConflictAction.showDiff:
              if (!canShowDiff) {
                showEditorSnackBar(context, "无法展示文件夹差异");
                return;
              }
              final shown = await _showUploadDiff(
                context,
                sourcePath: node.id,
                targetPath: targetPath,
              );
              if (!shown) {
                showEditorSnackBar(context, "无法展示差异");
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
          await _deleteBoardPath(targetPath, node.data is FolderItem);
        }

        if (node.data is FolderItem) {
          await ref
              .read(boardProvider.notifier)
              .uploadFolder(node.id, targetPath);
        } else {
          final bytes = await File(node.id).readAsBytes();
          ref
              .read(fileTransferProgressProvider.notifier)
              .start(
                direction: FileTransferDirection.upload,
                scope: FileTransferScope.file,
                totalFiles: nodes.length,
                message: '准备上传文件',
              );
          await ref
              .read(boardProvider.notifier)
              .writeFileBytesWithProgress(
                targetPath,
                bytes,
                currentFile: node.id,
                index: i + 1,
                totalFiles: nodes.length,
              );
        }
        uploaded++;
      }

      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(message: '上传完成：$uploaded 个，跳过：$skipped 个');
      showEditorSnackBar(context, "上传完成：$uploaded 个，跳过：$skipped 个");
    } catch (error) {
      ref.read(fileTransferProgressProvider.notifier).fail('上传失败：$error');
      rethrow;
    }
  }

  Future<void> uploadLocalPaths(
    BuildContext context,
    List<String> sourcePaths, {
    String? boardFolderPath,
  }) async {
    if (sourcePaths.isEmpty) return;

    final boardFolderTarget =
        boardFolderPath ??
        ref.read(boardProvider.notifier).getFocusFolderNode()?.id;
    FileConflictAction? conflictPolicy;
    var uploaded = 0;
    var skipped = 0;

    try {
      for (var i = 0; i < sourcePaths.length; i++) {
        final sourcePath = sourcePaths[i];
        final isFolder = await Directory(sourcePath).exists();
        final targetPath = buildBoardUploadTargetPath(
          sourcePath: sourcePath,
          boardFolderPath: boardFolderTarget,
        );
        final exists = await _boardPathExists(targetPath, isFolder);
        if (exists) {
          final action = await _resolveConflict(
            context,
            policy: conflictPolicy,
            sourcePath: sourcePath,
            targetPath: targetPath,
            isUpload: true,
          );
          switch (action) {
            case FileConflictAction.cancel:
              showEditorSnackBar(context, "已取消上传");
              return;
            case FileConflictAction.showDiff:
              showEditorSnackBar(context, "无法展示差异");
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
          await _deleteBoardPath(targetPath, isFolder);
        }

        if (isFolder) {
          await ref
              .read(boardProvider.notifier)
              .uploadFolder(sourcePath, targetPath);
        } else {
          final bytes = await File(sourcePath).readAsBytes();
          ref
              .read(fileTransferProgressProvider.notifier)
              .start(
                direction: FileTransferDirection.upload,
                scope: FileTransferScope.file,
                totalFiles: sourcePaths.length,
                message: '准备上传文件',
              );
          await ref
              .read(boardProvider.notifier)
              .writeFileBytesWithProgress(
                targetPath,
                bytes,
                currentFile: sourcePath,
                index: i + 1,
                totalFiles: sourcePaths.length,
              );
        }
        uploaded++;
      }

      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(message: '上传完成：$uploaded 个，跳过：$skipped 个');
      showEditorSnackBar(context, "上传完成：$uploaded 个，跳过：$skipped 个");
    } catch (error) {
      ref.read(fileTransferProgressProvider.notifier).fail('上传失败：$error');
      rethrow;
    }
  }

  Future<void> importExternalPaths(
    BuildContext context,
    List<String> sourcePaths, {
    String? localFolderPath,
  }) async {
    if (sourcePaths.isEmpty) return;
    final localWorkspace = state;
    if (localWorkspace == null) {
      showEditorSnackBar(context, "先打开一个本地项目");
      return;
    }

    final localFolderTarget = localFolderPath ?? getFocusFolderNode()?.id;
    final targetFolder = localFolderTarget ?? localWorkspace.path;
    FileConflictAction? conflictPolicy;
    var imported = 0;
    var skipped = 0;

    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.download,
          scope: FileTransferScope.folder,
          totalFiles: sourcePaths.length,
          message: '准备导入文件',
        );

    try {
      for (var i = 0; i < sourcePaths.length; i++) {
        final sourcePath = sourcePaths[i];
        final sourceDir = Directory(sourcePath);
        final isFolder = await sourceDir.exists();
        final targetPath = path.join(targetFolder, path.basename(sourcePath));
        final exists = isFolder
            ? await Directory(targetPath).exists()
            : await File(targetPath).exists();
        if (exists) {
          final action = await _resolveConflict(
            context,
            policy: conflictPolicy,
            sourcePath: sourcePath,
            targetPath: targetPath,
            isUpload: false,
          );
          switch (action) {
            case FileConflictAction.cancel:
              showEditorSnackBar(context, "已取消导入");
              return;
            case FileConflictAction.showDiff:
              showEditorSnackBar(context, "无法展示差异");
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
          await _deleteLocalPath(targetPath);
        }

        ref
            .read(fileTransferProgressProvider.notifier)
            .startFile(
              file: sourcePath,
              index: i + 1,
              totalFiles: sourcePaths.length,
              bytesTotal: 0,
            );
        if (isFolder) {
          await _copyDirectory(sourceDir, Directory(targetPath));
        } else {
          final targetFile = File(targetPath);
          await targetFile.parent.create(recursive: true);
          await File(sourcePath).copy(targetPath);
        }
        imported++;
      }

      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(message: '导入完成：$imported 个，跳过：$skipped 个');
      showEditorSnackBar(context, "导入完成：$imported 个，跳过：$skipped 个");
    } catch (error) {
      ref.read(fileTransferProgressProvider.notifier).fail('导入失败：$error');
      rethrow;
    }
  }

  Future<void> moveLocalNodes(
    BuildContext context,
    List<TreeNode<FileSystemItem>> nodes,
    String targetFolder,
  ) async {
    final movableNodes = nodes
        .where((node) => !_isLocalNodeAlreadyInTargetFolder(node, targetFolder))
        .toList(growable: false);
    if (movableNodes.isEmpty) return;
    if (!await Directory(targetFolder).exists()) {
      showEditorSnackBar(context, "目标文件夹不存在：$targetFolder");
      return;
    }

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
          message: '准备移动文件',
        );

    try {
      for (var i = 0; i < movableNodes.length; i++) {
        final node = movableNodes[i];
        final sourcePath = node.id;
        final targetPath = path.join(targetFolder, path.basename(sourcePath));
        if (path.equals(sourcePath, targetPath)) {
          skipped++;
          continue;
        }
        if (node.data is FolderItem &&
            _isLocalPathInside(targetFolder, sourcePath)) {
          showEditorSnackBar(context, "不能将文件夹移动到自身或子文件夹中");
          skipped++;
          continue;
        }

        final targetExists =
            await FileSystemEntity.type(targetPath) !=
            FileSystemEntityType.notFound;
        if (targetExists) {
          final action = await _resolveConflict(
            context,
            policy: conflictPolicy,
            sourcePath: sourcePath,
            targetPath: targetPath,
            isUpload: false,
          );
          switch (action) {
            case FileConflictAction.cancel:
              showEditorSnackBar(context, "已取消移动");
              return;
            case FileConflictAction.showDiff:
              showEditorSnackBar(context, "无法展示移动差异");
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
          await _deleteLocalPath(targetPath);
        }

        ref
            .read(fileTransferProgressProvider.notifier)
            .startFile(
              file: sourcePath,
              index: i + 1,
              totalFiles: movableNodes.length,
              bytesTotal: 0,
            );
        if (node.data is FolderItem) {
          await Directory(sourcePath).rename(targetPath);
        } else {
          await File(sourcePath).rename(targetPath);
        }
        moved++;
      }

      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(message: '移动完成：$moved 个，跳过：$skipped 个');
      showEditorSnackBar(context, "移动完成：$moved 个，跳过：$skipped 个");
    } catch (error) {
      ref.read(fileTransferProgressProvider.notifier).fail('移动失败：$error');
      rethrow;
    }
  }

  Future<void> _deleteLocalPath(String targetPath) async {
    final type = await FileSystemEntity.type(targetPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(targetPath).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(targetPath).delete();
    }
  }

  bool _isLocalPathInside(String childPath, String parentPath) {
    final normalizedChild = path.normalize(path.absolute(childPath));
    final normalizedParent = path.normalize(path.absolute(parentPath));
    return path.isWithin(normalizedParent, normalizedChild) ||
        path.equals(normalizedParent, normalizedChild);
  }

  bool _isLocalNodeAlreadyInTargetFolder(
    TreeNode<FileSystemItem> node,
    String targetFolder,
  ) {
    final sourceParent = path.normalize(path.absolute(path.dirname(node.id)));
    final target = path.normalize(path.absolute(targetFolder));
    return path.equals(sourceParent, target);
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      final relativePath = path.relative(entity.path, from: source.path);
      final targetPath = path.join(target.path, relativePath);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  Future<bool> _boardPathExists(String targetPath, bool folder) async {
    try {
      if (folder) {
        await ref.read(boardProvider.notifier).getFileList(path: targetPath);
      } else {
        await ref.read(boardProvider.notifier).getFileBytes(targetPath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteBoardPath(String targetPath, bool folder) async {
    if (folder) {
      await ref.read(boardProvider.notifier).deleteFolder(targetPath);
    } else {
      await ref.read(boardProvider.notifier).deleteFile(targetPath);
    }
  }

  Future<FileConflictAction> _resolveConflict(
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

  Future<bool> _showUploadDiff(
    BuildContext context, {
    required String sourcePath,
    required String targetPath,
  }) async {
    late final String content;
    late final String originContent;
    try {
      content = await local.getFileContent(sourcePath);
      originContent = await ref
          .read(boardProvider.notifier)
          .getFileContent(targetPath);
    } catch (_) {
      return false;
    }
    if (originContent == content) return false;

    final diff = computeDiff(originContent, content);
    if (!context.mounted) return false;
    final openedFile = await openFile(context, sourcePath);
    if (openedFile == null) return false;

    final controller = ref
        .read(editorControllerMapProvider.notifier)
        .getSelectedController();
    controller?.setGitDiffDecorations(
      addedRanges: diff.addedRanges,
      removedRanges: diff.removedRanges,
    );

    final provider = pendingUploadProviderMap.putIfAbsent(
      sourcePath,
      () => StateProvider<PendingUpload?>((ref) => null),
    );
    ref.read(provider.notifier).state = PendingUpload(
      diff: diff,
      localPath: sourcePath,
      targetPath: targetPath,
      content: content,
    );

    if (context.mounted && !ResponsiveBreakpoints.of(context).isDesktop) {
      context.go('/editor');
    }
    return true;
  }

  Future<File?> openFile(BuildContext context, String id) async {
    ref.read(localFileTreeViewControllerProvider).setSelectedNodeId(id);
    final node = ref.read(localFileTreeViewControllerProvider).findNodeById(id);
    if (node == null || node.data is! FileItem) return null;
    File file = File(id);
    if (context.mounted) {
      await ref
          .read(tabbedViewControllerProvider.notifier)
          .openFile(context, file: file);
    }
    return file;
  }

  Future<void> _uploadSelectedLocalItem(
    BuildContext context, {
    TabData? selectedTab,
  }) async {
    TreeNode<FileSystemItem>? selectedFolder;
    TreeNode<FileSystemItem>? selectedFile;
    if (selectedTab == null) {
      selectedFolder = getFocusFolderNode();
      selectedFile = getFocusFileNode();
    }

    final selected = selectedFile ?? selectedFolder;
    if (selected == null && selectedTab == null) {
      showEditorSnackBar(context, "先选择一个本地文件或文件夹");
      return;
    }

    final TreeNode<FileSystemItem>? boardFolderTarget = ref
        .read(boardProvider.notifier)
        .getFocusFolderNode();

    if (selected?.data is FileItem || selectedTab != null) {
      final String sourcePath = selected?.id ?? selectedTab!.value.filePath;
      final targetPath = buildBoardUploadTargetPath(
        sourcePath: sourcePath,
        boardFolderPath: boardFolderTarget?.id,
      );

      String content;
      try {
        content = await local.getFileContent(sourcePath);
      } on FileSystemException {
        await _uploadLocalFileBytes(sourcePath, targetPath);
        if (!context.mounted) return;
        showEditorSnackBar(context, "已上传到设备：$targetPath");
        return;
      }

      String? originContent;
      try {
        originContent = await ref
            .read(boardProvider.notifier)
            .getFileContent(targetPath);
      } catch (_) {}
      if (originContent != null && originContent != content) {
        final diff = computeDiff(originContent, content);

        if (ref.read(uploadConfirmStyleProvider) == 'dialog') {
          final confirmed = await showDiffConfirmDialog(
            context,
            diff: diff,
            targetPath: targetPath,
            isUpload: true,
          );
          if (!confirmed) {
            showEditorSnackBar(context, "已取消上传");
            return;
          }
        } else {
          await _showUploadDiff(
            context,
            sourcePath: selected?.id ?? selectedTab!.value.filePath,
            targetPath: targetPath,
          );
          return;
        }
      }

      try {
        ref
            .read(fileTransferProgressProvider.notifier)
            .start(
              direction: FileTransferDirection.upload,
              scope: FileTransferScope.file,
              totalFiles: 1,
              message: '准备上传文件',
            );
        await ref
            .read(boardProvider.notifier)
            .writeFileBytesWithProgress(
              targetPath,
              utf8.encode(content),
              currentFile: sourcePath,
              index: 1,
              totalFiles: 1,
            );
        ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
        ref
            .read(fileTransferProgressProvider.notifier)
            .complete(message: '已上传到设备：$targetPath');
      } catch (error) {
        ref.read(fileTransferProgressProvider.notifier).fail('上传失败：$error');
        rethrow;
      }

      showEditorSnackBar(context, "已上传到设备：$targetPath");
    } else if (selected?.data is FolderItem) {
      final targetPath = buildBoardUploadTargetPath(
        sourcePath: selected!.id,
        boardFolderPath: boardFolderTarget?.id,
      );
      try {
        await ref
            .read(boardProvider.notifier)
            .uploadFolder(selected.id, targetPath);
        ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
        ref
            .read(fileTransferProgressProvider.notifier)
            .complete(message: '已上传文件夹到设备：$targetPath');
      } catch (error) {
        ref.read(fileTransferProgressProvider.notifier).fail('上传失败：$error');
        rethrow;
      }

      showEditorSnackBar(context, "已上传文件夹到设备：$targetPath");
    }
  }

  Future<void> uploadSelectedLocalFileItem(
    BuildContext context, {
    TabData? selectedTab,
  }) async {
    TreeNode<FileSystemItem>? selectedFolder;
    TreeNode<FileSystemItem>? selectedFile;
    if (selectedTab == null) {
      selectedFolder = getFocusFolderNode();
      selectedFile = getFocusFileNode();
    }

    final selected = selectedFile ?? selectedFolder;
    if (selected == null && selectedTab == null) {
      showEditorSnackBar(context, "先选择一个本地文件或文件夹");
      return;
    }

    if (selected?.data is FileItem || selectedTab != null) {
      final String sourcePath = selected?.id ?? selectedTab!.value.filePath;
      String content;
      try {
        content = await local.getFileContent(sourcePath);
      } on FileSystemException {
        await _uploadSelectedLocalItem(context, selectedTab: selectedTab);
        return;
      }
      // 检查 Local 文件在编辑器中显示的内容是否与实际内容一致
      if ((ref
                  .read(editorControllerMapProvider)[selected?.id ??
                      selectedTab?.value.filePath]
                  ?.text !=
              null) &&
          (content !=
              ref
                  .read(editorControllerMapProvider)[selected?.id ??
                      selectedTab?.value.filePath]!
                  .text)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.file_upload_outlined),
            title: const Text("本地文件内容不一致或编辑器内的更改未保存"),
            content: Text(
              "文件“${selected?.id ?? selectedTab?.value.filePath}”在编辑器中的内容与实际文件内容不一致，可能你做出了更改但没有保存或被外部程序所更改\n为了确保正确展示本地文件与板载文件间的差异，必须选择其一覆盖：",
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const Text("取消上传"),
              ),
              TextButton(
                onPressed: () {
                  saveCurrentFile();
                  _uploadSelectedLocalItem(context, selectedTab: selectedTab);
                  context.pop();
                },
                child: const Text("编辑器中内容"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () {
                  ref
                          .read(editorControllerMapProvider)[selected?.id ??
                              selectedTab?.value.filePath]
                          ?.text =
                      content;
                  saveCurrentFile();
                  _uploadSelectedLocalItem(context, selectedTab: selectedTab);
                  context.pop();
                },
                child: const Text("实际内容"),
              ),
            ],
          ),
        );
      } else {
        _uploadSelectedLocalItem(context, selectedTab: selectedTab);
      }
    } else {
      _uploadSelectedLocalItem(context, selectedTab: selectedTab);
    }
  }

  Future<void> _uploadLocalFileBytes(
    String sourcePath,
    String targetPath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    try {
      ref
          .read(fileTransferProgressProvider.notifier)
          .start(
            direction: FileTransferDirection.upload,
            scope: FileTransferScope.file,
            totalFiles: 1,
            message: '准备上传文件',
          );
      await ref
          .read(boardProvider.notifier)
          .writeFileBytesWithProgress(
            targetPath,
            bytes,
            currentFile: sourcePath,
            index: 1,
            totalFiles: 1,
          );
      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(fileTransferProgressProvider.notifier)
          .complete(message: '已上传到设备：$targetPath');
    } catch (error) {
      ref.read(fileTransferProgressProvider.notifier).fail('上传失败：$error');
      rethrow;
    }
  }
}

final StateNotifierProvider<FileNotifier, Directory?> fileProvider =
    StateNotifierProvider((ref) => FileNotifier(ref));

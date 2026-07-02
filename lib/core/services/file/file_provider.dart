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
          await openFile(context, selected?.id ?? selectedTab?.value.filePath);

          // 得益于 openFile 的行为，此时可以保证选中的标签页已经是所需的标签页
          final controller = ref
              .read(editorControllerMapProvider.notifier)
              .getSelectedController();
          controller?.setGitDiffDecorations(
            addedRanges: diff.addedRanges,
            removedRanges: diff.removedRanges,
          );

          final pendingUpload = PendingUpload(
            diff: diff,
            localPath: selected?.id ?? selectedTab?.value.filePath,
            targetPath: targetPath,
            content: content,
          );
          ref
                  .read(
                    pendingUploadProviderMap[selected?.id ??
                            selectedTab?.value.filePath]!
                        .notifier,
                  )
                  .state =
              pendingUpload;

          if (!ResponsiveBreakpoints.of(context).isDesktop) {
            context.go('/editor');
          }
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

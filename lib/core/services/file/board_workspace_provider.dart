import 'dart:io' as io;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/ui_utils.dart';
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:super_tree/super_tree.dart';
import 'package:tabbed_view/tabbed_view.dart';

class BoardWorkspaceNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  static final _boardPath = path.Context(style: path.Style.posix);

  final Ref ref;

  BoardWorkspaceNotifier(this.ref) : super(const []);

  Future<List<Map<String, String>>> getFileList({String path = "/"}) async {
    final entries = await ref
        .read(boardFileBackendProvider)
        .listDirectory(path: path);
    return entries.map((entry) => entry.toLegacyMap()).toList();
  }

  Future<String> getFileContent(String path) async {
    return ref.read(boardFileBackendProvider).readTextFile(path);
  }

  Future<Uint8List> getFileBytes(String path) async {
    return ref.read(boardFileBackendProvider).readFileBytes(path);
  }

  Future<String> writeFile(String targetPath, String content) async {
    await ref.read(boardFileBackendProvider).writeTextFile(targetPath, content);
    return 'SaveFileSuccessfully';
  }

  Future<String> writeFileBytes(String targetPath, List<int> bytes) async {
    await ref.read(boardFileBackendProvider).writeFileBytes(targetPath, bytes);
    return 'SaveFileSuccessfully';
  }

  Future<String> deleteFile(String path) async {
    await ref.read(boardFileBackendProvider).deleteFile(path);
    return 'DeleteFileSuccessfully';
  }

  Future<String> deleteFolder(String path) async {
    await ref.read(boardFileBackendProvider).deleteFolder(path);
    return 'DeleteDirSuccessfully';
  }

  Future<String> rename(String path, String newName) async {
    await ref.read(boardFileBackendProvider).rename(path, newName);
    return 'RenameSuccessfully';
  }

  Future<void> createFolder(String path) async {
    await ref.read(boardFileBackendProvider).createFolder(path);
  }

  Future<List<Map<String, String>>> lisFolderRecursive({
    String path = "/",
  }) async {
    final entries = await ref
        .read(boardFileBackendProvider)
        .listTree(path: path);
    return entries.map((entry) => entry.toLegacyMap()).toList();
  }

  Future<void> uploadFolder(String localPath, String remotePath) async {
    final dir = io.Directory(localPath);
    final entities = await dir.list(recursive: true).toList();
    final createdDirs = <String>{};

    for (final entity in entities) {
      final relativePath = path
          .relative(entity.path, from: localPath)
          .replaceAll('\\', '/');
      final remoteEntityPath = _boardPath.join(remotePath, relativePath);
      final parentDir = _boardPath.dirname(remoteEntityPath);

      if (entity is io.Directory) {
        debugPrint('[BoardWS] Creating remote dir: $remoteEntityPath');
        try {
          await createFolder(remoteEntityPath);
          createdDirs.add(remoteEntityPath);
        } catch (e) {
          debugPrint('[BoardWS] Failed to create dir: $e');
        }
      } else if (entity is io.File) {
        if (!createdDirs.contains(parentDir)) {
          debugPrint('[BoardWS] Creating parent dir: $parentDir');
          try {
            await createFolder(parentDir);
            createdDirs.add(parentDir);
          } catch (e) {
            debugPrint('[BoardWS] Failed to create parent dir: $e');
          }
        }
        debugPrint('[BoardWS] Uploading file: $remoteEntityPath');
        await writeFileBytes(remoteEntityPath, await entity.readAsBytes());
        debugPrint('[BoardWS] Uploaded: $remoteEntityPath');
      }
    }
  }

  Future<void> downloadFolder(String remotePath, String localPath) async {
    final items = await lisFolderRecursive(path: remotePath);

    final localDir = io.Directory(localPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    for (final item in items) {
      final relativePath = _boardPath
          .relative(item['path']!, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = path.join(localPath, relativePath);

      if (item['type'] == 'folder') {
        await io.Directory(localItemPath).create(recursive: true);
      } else {
        debugPrint('[BoardWS] Downloading: ${item['path']}');
        final bytes = await getFileBytes(item['path']!);
        final file = io.File(localItemPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        debugPrint('[BoardWS] Downloaded: $localItemPath');
      }
    }
  }

  TreeNode<FileSystemItem>? getFocusFileNode() {
    String focusNodeId =
        ref.read(boardFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(boardFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FileItem) {
      return focusNode;
    } else {
      return null;
    }
  }

  TreeNode<FileSystemItem>? getFocusFolderNode() {
    String focusNodeId =
        ref.read(boardFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(boardFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FolderItem) {
      return focusNode;
    } else {
      return ref
          .read(boardFileTreeViewControllerProvider)
          .findNodeById(_boardPath.dirname(focusNodeId));
    }
  }

  Future<File?> openFile(BuildContext context, String id) async {
    ref.read(boardFileTreeViewControllerProvider).setSelectedNodeId(id);
    final node = ref.read(boardFileTreeViewControllerProvider).findNodeById(id);
    if (node == null || node.data is! FileItem) return null;
    final file = await board.getLocalFile(node.id);
    final content = await ref
        .read(boardWorkspaceProvider.notifier)
        .getFileContent(id);
    await file.writeAsString(content);
    if (context.mounted) {
      await ref
          .read(tabbedViewControllerProvider.notifier)
          .openFile(context, file: file, isBoardFile: true, boardFilePath: id);
    }
    return file;
  }

  Future<void> saveFile() async {
    final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
    final value = nowTab?.value;
    if (value is TabDataValue && value.type == "file") {
      if (value.isBoardFile == true && value.boardFilePath != null) {
        await ref
            .read(boardWorkspaceProvider.notifier)
            .writeFile(value.boardFilePath!, value.editorController!.text);
        ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
      } else {
        await value.file!.writeAsString(value.editorController!.text);
      }
      ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
    }
  }

  Future<void> _downloadSelectedBoardItem(
    BuildContext context, {
    TabData? selectedTab,
  }) async {
    TreeNode<FileSystemItem>? selectedFile = getFocusFileNode();
    TreeNode<FileSystemItem>? selectedFolder = getFocusFolderNode();
    if (selectedTab == null) {
      selectedFile = getFocusFileNode();
      selectedFolder = getFocusFolderNode();
    }
    final selected = selectedFile ?? selectedFolder;
    final localWorkspace = ref.read(localWorkspaceProvider);
    if (selected == null && selectedTab == null) {
      showEditorSnackBar(context, "先选择一个设备文件或文件夹");
      return;
    }
    if (localWorkspace == null) {
      showEditorSnackBar(context, "先打开一个本地项目");
      return;
    }

    final localFolderTarget = ref
        .read(localWorkspaceProvider.notifier)
        .getFocusFolderNode();
    final targetPath = localFolderTarget?.id != null
        ? path.join(
            localFolderTarget!.id,
            _boardPath.basename(
              (selected?.id ?? selectedTab?.value.filePath).toString(),
            ),
          )
        : path.join(
            localWorkspace.path,
            _boardPath.basename(
              (selected?.id ?? selectedTab?.value.filePath).toString(),
            ),
          );

    if (selected?.data is FileItem || selectedTab != null) {
      final content = await getFileContent(
        selected?.id ?? selectedTab?.value.filePath,
      );

      String? originContent;
      if (await File(targetPath).exists()) {
        try {
          originContent = await File(targetPath).readAsString();
        } catch (_) {}
      }
      if (originContent != null && originContent != content) {
        final diff = computeDiff(originContent, content);

        if (ref.read(uploadConfirmStyleProvider) == 'dialog') {
          final confirmed = await showDiffConfirmDialog(
            context,
            diff: diff,
            targetPath: targetPath,
            isUpload: false,
          );
          if (!confirmed) {
            showEditorSnackBar(context, "已取消下载");
            return;
          }
        } else {
          final correspondingFile = await openFile(
            context,
            selected?.id ?? selectedTab?.value.filePath,
          );

          final controller = ref
              .read(editorControllerMapProvider.notifier)
              .getSelectedController();

          controller!.setGitDiffDecorations(
            addedRanges: diff.addedRanges,
            removedRanges: diff.removedRanges,
          );

          final correspondingFilePath = (await board.getLocalFile(
            selected?.id ?? selectedTab?.value.filePath,
          )).path;

          final pendingDownload = PendingDownload(
            diff: diff,
            boardPath: selected?.id ?? selectedTab?.value.filePath,
            localPath: targetPath,
            correspondingPath: correspondingFile!.path,
            content: content,
          );
          ref
                  .read(
                    pendingDownloadProviderMap[correspondingFilePath]!.notifier,
                  )
                  .state =
              pendingDownload;

          if (!ResponsiveBreakpoints.of(context).isDesktop) {
            context.go('/editor');
          }
          return;
        }
      }

      local.writeFile(targetPath, content);

      showEditorSnackBar(context, "已下载到本地：$targetPath");
    } else {
      await ref
          .read(boardWorkspaceProvider.notifier)
          .downloadFolder(
            selected?.id ?? selectedTab?.value.filePath,
            targetPath,
          );

      showEditorSnackBar(context, "已下载文件夹到本地：$targetPath");
    }

    ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
  }

  Future<void> downloadSelectedBoardItem(
    BuildContext context, {
    TabData? selectedTab,
  }) async {
    TreeNode<FileSystemItem>? selectedFile = getFocusFileNode();
    TreeNode<FileSystemItem>? selectedFolder = getFocusFolderNode();
    if (selectedTab == null) {
      selectedFile = getFocusFileNode();
      selectedFolder = getFocusFolderNode();
    }

    final selected = selectedFile ?? selectedFolder;
    final localWorkspace = ref.read(localWorkspaceProvider);
    if (selected == null && selectedTab == null) {
      showEditorSnackBar(context, "先选择一个设备文件或文件夹");
      return;
    }
    if (localWorkspace == null) {
      showEditorSnackBar(context, "先打开一个本地项目");
      return;
    }

    if (selected?.data is FileItem || selectedTab != null) {
      final content = await getFileContent(
        selected?.id ?? selectedTab?.value.filePath,
      );

      final correspondingFilePath = (await board.getLocalFile(
        selected?.id ?? selectedTab?.value.filePath,
      )).path;

      if ((ref.read(editorControllerMapProvider)[correspondingFilePath]?.text !=
              null) &&
          (content !=
              ref
                  .read(editorControllerMapProvider)[correspondingFilePath]!
                  .text)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.file_download_outlined),
            title: const Text("设备文件内容不一致或编辑器内的更改未保存"),
            content: Text(
              "设备文件“${selected?.id ?? selectedTab?.value.filePath}”在编辑器中的内容与实际文件内容不一致，可能你做出了更改但没有保存或被外部程序所更改\n为了确保正确展示本地文件与板载文件间的差异，必须选择其一覆盖：",
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const Text("取消上传"),
              ),
              TextButton(
                onPressed: () {
                  saveFile();
                  _downloadSelectedBoardItem(context, selectedTab: selectedTab);
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
                          .read(
                            editorControllerMapProvider,
                          )[correspondingFilePath]
                          ?.text =
                      content;
                  saveFile();
                  _downloadSelectedBoardItem(context, selectedTab: selectedTab);
                  context.pop();
                },
                child: const Text("实际内容"),
              ),
            ],
          ),
        );
      } else {
        _downloadSelectedBoardItem(context, selectedTab: selectedTab);
      }
    } else {
      _downloadSelectedBoardItem(context, selectedTab: selectedTab);
    }
  }

  void clear() {
    state = const [];
  }
}

final StateNotifierProvider<
  BoardWorkspaceNotifier,
  List<TreeNode<FileSystemItem>>
>
boardWorkspaceProvider = StateNotifierProvider(
  (ref) => BoardWorkspaceNotifier(ref),
);

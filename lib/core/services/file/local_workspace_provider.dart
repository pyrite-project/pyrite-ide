import 'dart:io';
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
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as utils;
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:super_tree/super_tree.dart';
import 'package:tabbed_view/tabbed_view.dart';

class LocalWorkspaceNotifier extends StateNotifier<Directory?> {
  final Ref ref;
  LocalWorkspaceNotifier(this.ref) : super(null);

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

  Future<Stream<FileSystemEntity>> getFilesList({String? path}) async {
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

  void saveAs() async {
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

  Future<String> createFile(
    String name,
    TreeNode<FileSystemItem>? parentPath,
  ) async {
    final String actualPath;
    if (parentPath != null) {
      actualPath = await local.createFileWithUniqueName(
        path.join(parentPath.id, "new_file"),
      );
    } else {
      actualPath = await local.createFileWithUniqueName(
        path.join(state!.path, "new_file"),
      );
    }
    final isIgnored = (await local.gitIgnoredPaths([
      actualPath,
    ])).contains(path.normalize(actualPath));

    if (parentPath != null) {
      ref
          .read(localFileTreeViewControllerProvider)
          .addChild(
            parentPath,
            TreeNode(
              id: actualPath,
              data: local.LocalFileItem(
                actualPath.split(local.getPattern()).last,
                isGitIgnored: isIgnored,
              ),
            ),
          );
    } else {
      ref
          .read(localFileTreeViewControllerProvider)
          .addRoot(
            TreeNode(
              id: actualPath,
              data: local.LocalFileItem(
                actualPath.split(local.getPattern()).last,
                isGitIgnored: isIgnored,
              ),
            ),
          );
    }
    return actualPath;
  }

  Future<String> createFolder(
    String name,
    TreeNode<FileSystemItem>? parentPath,
  ) async {
    final String actualPath;
    if (parentPath != null) {
      actualPath = await local.createFolderWithUniqueName(
        path.join(parentPath.id, "new_folder"),
      );
    } else {
      actualPath = await local.createFolderWithUniqueName(
        path.join(state!.path, "new_folder"),
      );
    }
    final isIgnored = (await local.gitIgnoredPaths([
      actualPath,
    ])).contains(path.normalize(actualPath));

    if (parentPath != null) {
      ref
          .read(localFileTreeViewControllerProvider)
          .addChild(
            parentPath,
            TreeNode(
              id: actualPath,
              canLoadChildren: true,
              data: local.LocalFolderItem(
                path.basename(actualPath),
                isGitIgnored: isIgnored,
              ),
            ),
          );
    } else {
      ref
          .read(localFileTreeViewControllerProvider)
          .addRoot(
            TreeNode(
              id: actualPath,
              canLoadChildren: true,
              data: local.LocalFolderItem(
                path.basename(actualPath),
                isGitIgnored: isIgnored,
              ),
            ),
          );
    }
    return actualPath;
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

    final TreeNode<FileSystemItem>? boardFolderTarget = getFocusFolderNode();

    if (selected?.data is FileItem || selectedTab != null) {
      final String content = await local.getFileContent(
        selected?.id ?? selectedTab?.value.filePath,
      );
      final targetPath = (boardFolderTarget?.id != null)
          ? "${boardFolderTarget!.id}/${path.basename(selected?.id ?? selectedTab?.value.filePath)}"
          : "/${path.basename(selected?.id ?? selectedTab?.value.filePath)}";

      String? originContent;
      try {
        originContent = await ref
            .read(boardWorkspaceProvider.notifier)
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

      await ref
          .read(boardWorkspaceProvider.notifier)
          .writeFile(targetPath, content);
      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();

      showEditorSnackBar(context, "已上传到设备：$targetPath");
    } else if (selected?.data is FolderItem) {
      final targetPath = (boardFolderTarget?.id != null)
          ? "${boardFolderTarget!.id}/${path.basename(selected!.id)}"
          : "/${path.basename(selected!.id)}";
      await ref
          .read(boardWorkspaceProvider.notifier)
          .uploadFolder(selected!.id, targetPath);
      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();

      showEditorSnackBar(context, "已上传文件夹到设备：$targetPath");
    }
  }

  Future<void> uploadSelectedLocalItem(
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

    final TreeNode<FileSystemItem>? boardFolderTarget = getFocusFolderNode();
    if (selected?.data is FileItem || selectedTab != null) {
      final String content = await local.getFileContent(
        selected?.id ?? selectedTab?.value.filePath,
      );
      final targetPath = (boardFolderTarget?.id != null)
          ? "${boardFolderTarget!.id}/${path.basename(selected?.id ?? selectedTab?.value)}"
          : "/${path.basename(selected?.id ?? selectedTab?.value.filePath)}";

      String? originContent;
      try {
        originContent = await ref
            .read(boardWorkspaceProvider.notifier)
            .getFileContent(targetPath);
      } catch (_) {}
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
                  saveFile();
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
                  saveFile();
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
}

final StateNotifierProvider<LocalWorkspaceNotifier, Directory?>
localWorkspaceProvider = StateNotifierProvider(
  (ref) => LocalWorkspaceNotifier(ref),
);

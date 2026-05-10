import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as utils;
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:super_tree/super_tree.dart';
import 'package:tabbed_view/tabbed_view.dart';

class LocalWorkspaceNotifier extends StateNotifier<Directory?> {
  final Ref ref;
  LocalWorkspaceNotifier(this.ref) : super(null);

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

  void saveFile() {
    final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
    if (nowTab != null && nowTab.value.type == "file") {
      print(
        "debug: saveFileAction with file ${nowTab.value.filePath}, mpy device: ${nowTab.value.device!.micropython}",
      );
      if (nowTab.value.device.micropython && nowTab.value.device.file != null) {
        print("debug: save to board");
        ref
            .read(boardWorkspaceProvider.notifier)
            .writeFile(
              nowTab.value.device.file!,
              nowTab.value.editorController!.text,
            );
      } else {
        utils.writeFile(
          nowTab.value.file!,
          nowTab.value.editorController!.text,
        );
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
        path.join(state!.path, parentPath.id, "new_file"),
      );
    } else {
      actualPath = await local.createFileWithUniqueName(
        path.join(state!.path, "new_file"),
      );
    }

    if (parentPath != null) {
      ref
          .read(localFileTreeViewControllerProvider)
          .addChild(
            parentPath,
            TreeNode(
              id: actualPath,
              data: FileItem(actualPath.split(local.getPattern()).last),
            ),
          );
    } else {
      ref
          .read(localFileTreeViewControllerProvider)
          .addRoot(
            TreeNode(
              id: actualPath,
              data: FileItem(actualPath.split(local.getPattern()).last),
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
        path.join(state!.path, parentPath.id, "new_folder"),
      );
    } else {
      actualPath = await local.createFolderWithUniqueName(
        path.join(state!.path, "new_folder"),
      );
    }

    if (parentPath != null) {
      ref
          .read(localFileTreeViewControllerProvider)
          .addChild(
            parentPath,
            TreeNode(
              id: actualPath,
              canLoadChildren: true,
              data: FolderItem(path.basename(actualPath)),
            ),
          );
    } else {
      ref
          .read(localFileTreeViewControllerProvider)
          .addRoot(
            TreeNode(
              id: actualPath,
              canLoadChildren: true,
              data: FolderItem(path.basename(actualPath)),
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
}

final StateNotifierProvider<LocalWorkspaceNotifier, Directory?>
localWorkspaceProvider = StateNotifierProvider(
  (ref) => LocalWorkspaceNotifier(ref),
);
